from odoo import api, fields, models, _
from odoo.exceptions import UserError, ValidationError


class AcpecFuelCarnetTransfer(models.Model):
    _name = 'acpec.fuel.carnet.transfer'
    _description = 'Transfert de carnets FuelToken'
    _inherit = ['mail.thread', 'mail.activity.mixin', 'acpec.fuel.public.code.mixin']
    _order = 'id desc'

    name = fields.Char(string='Référence', default='New', readonly=True, copy=False)
    source_wallet_id = fields.Many2one(
        'acpec.fuel.wallet', string='Compte source',
        required=True, index=True, ondelete='restrict', tracking=True,
    )
    source_partner_id = fields.Many2one(
        'res.partner', related='source_wallet_id.partner_id',
        store=True, readonly=True, index=True,
    )
    dest_wallet_id = fields.Many2one(
        'acpec.fuel.wallet', string='Compte destinataire',
        required=True, index=True, ondelete='restrict', tracking=True,
    )
    dest_partner_id = fields.Many2one(
        'res.partner', related='dest_wallet_id.partner_id',
        store=True, readonly=True, index=True,
    )
    company_id = fields.Many2one(
        'res.company', string='Société',
        required=True, default=lambda self: self.env.company, index=True,
    )
    currency_id = fields.Many2one(
        'res.currency', related='company_id.currency_id',
        store=True, readonly=True,
    )
    state = fields.Selection([
        ('draft', 'Brouillon'),
        ('confirmed', 'Confirmé'),
        ('cancelled', 'Annulé'),
    ], string='État', default='draft', required=True, index=True, tracking=True)
    line_ids = fields.One2many(
        'acpec.fuel.carnet.transfer.line', 'transfer_id', string='Lignes',
    )
    note = fields.Text(string='Note')
    idempotency_key = fields.Char(string='Clé idempotence', index=True, copy=False)
    confirmed_at = fields.Datetime(string='Confirmé le', readonly=True, copy=False)
    confirmed_by = fields.Many2one(
        'res.users', string='Confirmé par', readonly=True, copy=False,
    )
    amount_total = fields.Monetary(
        string='Montant total', compute='_compute_totals', store=True,
    )
    face_qty_total = fields.Integer(
        string='Faces totales', compute='_compute_totals', store=True,
    )

    _idempotency_source_wallet_unique = models.Constraint(
        'UNIQUE(source_wallet_id, idempotency_key)',
        "Cette operation de transfert a deja ete enregistree pour ce compte source.",
    )

    _legacy_sql_constraints_disabled = [
        (
            'idempotency_unique',
            'unique(idempotency_key)',
            "Cette opération de transfert a déjà été enregistrée (clé idempotence dupliquée).",
        ),
    ]

    def init(self):
        self.env.cr.execute(
            'ALTER TABLE acpec_fuel_carnet_transfer '
            'DROP CONSTRAINT IF EXISTS acpec_fuel_carnet_transfer_idempotency_unique'
        )

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if vals.get('name', 'New') == 'New':
                vals['name'] = (
                    self.env['ir.sequence'].next_by_code('acpec.fuel.carnet.transfer') or 'New'
                )
            if not vals.get('public_code'):
                vals['public_code'] = self._create_unique_public_code(prefix='TRF', size=18)
        return super().create(vals_list)

    @api.depends('line_ids.qty_faces', 'line_ids.amount_total')
    def _compute_totals(self):
        for rec in self:
            rec.face_qty_total = sum(rec.line_ids.mapped('qty_faces'))
            rec.amount_total = sum(rec.line_ids.mapped('amount_total'))

    @api.constrains('source_wallet_id', 'dest_wallet_id', 'company_id')
    def _check_wallets(self):
        for rec in self:
            if rec.source_wallet_id == rec.dest_wallet_id:
                raise ValidationError(
                    _('Le compte source et le compte destinataire doivent être différents.')
                )
            if rec.source_wallet_id.company_id != rec.company_id:
                raise ValidationError(
                    _('Le compte source doit appartenir à la même société que le transfert.')
                )
            if rec.dest_wallet_id.company_id != rec.company_id:
                raise ValidationError(
                    _('Le compte destinataire doit appartenir à la même société que le transfert.')
                )

    def action_confirm(self):
        """Confirme le transfert : débite le wallet source, crédite le wallet dest.

        Règles métier appliquées :
        - Le transfert porte sur des carnets complets (qty_faces multiple de face_count).
        - Les faces doivent être disponibles (qty_available), donc ni en QR actif ni bloquées.
        - La ligne de faces ne doit pas être expirée.
        - L'expiration d'origine est conservée sur la face_line de destination.
        - Le lien vers le lot d'achat d'origine est conservé.
        - Deux transactions sont enregistrées : une par wallet (source et dest).
        """
        self.ensure_one()
        if self.state != 'draft':
            raise UserError(_('Seul un transfert en brouillon peut être confirmé.'))
        if not self.line_ids:
            raise UserError(_('Le transfert doit contenir au moins une ligne.'))

        FaceLine = self.env['acpec.fuel.face.line'].sudo()
        Tx = self.env['acpec.fuel.transaction'].sudo()
        now = fields.Datetime.now()

        with self.env.cr.savepoint():
            self.env.cr.execute(
                'SELECT id FROM acpec_fuel_wallet WHERE id IN %s FOR UPDATE',
                [tuple((self.source_wallet_id | self.dest_wallet_id).ids)],
            )
            # Verrou pessimiste sur toutes les face_lines source pour éviter les conflits concurrents
            src_face_line_ids = tuple(self.line_ids.mapped('face_line_id').ids)
            if not src_face_line_ids:
                raise ValidationError(_('Aucune ligne de faces valide dans le transfert.'))
            self.env.cr.execute(
                'SELECT id FROM acpec_fuel_face_line WHERE id IN %s FOR UPDATE',
                [src_face_line_ids],
            )
            self.line_ids.mapped('face_line_id').invalidate_recordset()

            src_tx_lines = []
            dst_tx_lines = []

            for trf_line in self.line_ids:
                src_face_line = trf_line.face_line_id
                qty_to_transfer = trf_line.qty_faces
                face_count = trf_line.face_count

                # 1. Vérifier appartenance au wallet source
                if src_face_line.wallet_id != self.source_wallet_id:
                    raise ValidationError(_(
                        "La ligne de faces '%s' n'appartient pas au compte source."
                    ) % src_face_line.carnet_type_id.code)

                # 2. Vérifier non-expiration
                if src_face_line.expires_at and src_face_line.expires_at <= now:
                    raise ValidationError(_(
                        "La ligne de faces '%s' est expirée et ne peut pas être transférée."
                    ) % src_face_line.carnet_type_id.code)

                if (
                    src_face_line.qty_available != src_face_line.qty_initial
                    or src_face_line.qty_qr_active
                    or src_face_line.qty_qr_blocked
                    or src_face_line.qty_consumed
                    or src_face_line.qty_expired
                ):
                    raise ValidationError(_(
                        "Le transfert de '%s' n'est autorisé que pour un carnet intact "
                        "(%d disponibles sur %d initiaux)."
                    ) % (
                        src_face_line.carnet_type_id.code,
                        src_face_line.qty_available,
                        src_face_line.qty_initial,
                    ))

                # 3. Vérifier disponibilité (qty_available garantit que les faces ne sont pas en QR actif/bloqué)
                if src_face_line.qty_available < qty_to_transfer:
                    raise ValidationError(_(
                        "Faces insuffisantes pour '%s' : %d disponibles, %d demandées."
                    ) % (
                        src_face_line.carnet_type_id.code,
                        src_face_line.qty_available,
                        qty_to_transfer,
                    ))

                # 4. Vérifier carnets complets (multiple de face_count)
                if face_count and qty_to_transfer % face_count != 0:
                    raise ValidationError(_(
                        "Le transfert doit porter sur des carnets complets "
                        "(type '%s' : %d faces/carnet, %d faces demandées — non multiple)."
                    ) % (src_face_line.carnet_type_id.code, face_count, qty_to_transfer))

                # 5. Débiter le wallet source
                # qty_initial est réduit pour maintenir l'invariant de conservation :
                # qty_initial == qty_available + qty_qr_active + qty_qr_blocked + qty_consumed + qty_expired
                src_face_line.write({
                    'qty_initial': src_face_line.qty_initial - qty_to_transfer,
                    'qty_available': src_face_line.qty_available - qty_to_transfer,
                })

                # 6. Créditer le wallet destinataire (conserve expiration et lien achat d'origine)
                dest_face_line = FaceLine.credit_transferred(
                    dest_wallet=self.dest_wallet_id,
                    purchase_line=src_face_line.purchase_line_id,
                    carnet_type=src_face_line.carnet_type_id,
                    face_value=src_face_line.face_value,
                    qty=qty_to_transfer,
                    expires_at=src_face_line.expires_at,
                )

                # Traçabilité : lier la ligne de transfert à la face_line de destination
                trf_line.sudo().write({'dest_face_line_id': dest_face_line.id})

                src_tx_lines.append({
                    'face_line_id': src_face_line.id,
                    'purchase_id': src_face_line.purchase_id.id,
                    'purchase_line_id': src_face_line.purchase_line_id.id,
                    'transfer_id': self.id,
                    'face_value': src_face_line.face_value,
                    'qty': qty_to_transfer,
                })
                dst_tx_lines.append({
                    'face_line_id': dest_face_line.id,
                    'purchase_id': src_face_line.purchase_id.id,
                    'purchase_line_id': src_face_line.purchase_line_id.id,
                    'transfer_id': self.id,
                    'face_value': src_face_line.face_value,
                    'qty': qty_to_transfer,
                })

            # 7. Journaliser deux transactions (une par wallet)
            Tx.log(
                'transfert_carnet', self.company_id,
                wallet=self.source_wallet_id,
                transfer=self,
                lines=src_tx_lines,
                note=_('Transfert sortant vers %s.') % self.dest_partner_id.display_name,
                idempotency_key='SRC-%s' % (self.idempotency_key or self.name),
            )
            Tx.log(
                'transfert_carnet', self.company_id,
                wallet=self.dest_wallet_id,
                transfer=self,
                lines=dst_tx_lines,
                note=_('Transfert entrant de %s.') % self.source_partner_id.display_name,
                idempotency_key='DST-%s' % (self.idempotency_key or self.name),
            )

            self.write({
                'state': 'confirmed',
                'confirmed_at': now,
                'confirmed_by': self.env.user.id,
            })
        return True

    def action_cancel(self):
        self.ensure_one()
        if self.state == 'confirmed':
            raise UserError(_(
                "Un transfert déjà confirmé ne peut pas être annulé. "
                "Créez un transfert inverse si nécessaire."
            ))
        self.write({'state': 'cancelled'})
        return True


class AcpecFuelCarnetTransferLine(models.Model):
    _name = 'acpec.fuel.carnet.transfer.line'
    _description = 'Ligne de transfert de carnets FuelToken'
    _order = 'transfer_id, id'

    transfer_id = fields.Many2one(
        'acpec.fuel.carnet.transfer', string='Transfert',
        required=True, ondelete='cascade', index=True,
    )
    company_id = fields.Many2one(
        'res.company', related='transfer_id.company_id', store=True, readonly=True,
    )
    currency_id = fields.Many2one(
        'res.currency', related='transfer_id.currency_id', store=True, readonly=True,
    )
    face_line_id = fields.Many2one(
        'acpec.fuel.face.line', string='Ligne de faces source',
        required=True, index=True, ondelete='restrict',
    )
    carnet_type_id = fields.Many2one(
        'acpec.fuel.carnet.type',
        related='face_line_id.carnet_type_id', store=True, readonly=True,
    )
    face_value = fields.Monetary(
        related='face_line_id.face_value', store=True, readonly=True,
    )
    face_count = fields.Integer(
        related='face_line_id.carnet_type_id.face_count', store=True, readonly=True,
    )
    expires_at = fields.Datetime(
        related='face_line_id.expires_at', store=True, readonly=True,
    )
    carnet_qty = fields.Integer(string='Nombre de carnets', required=True)
    qty_faces = fields.Integer(
        string='Faces transférées', compute='_compute_qty', store=True,
    )
    amount_total = fields.Monetary(
        string='Montant', compute='_compute_qty', store=True,
    )
    dest_face_line_id = fields.Many2one(
        'acpec.fuel.face.line', string='Ligne de faces dest.',
        readonly=True, copy=False, index=True,
    )

    @api.depends('carnet_qty', 'face_count', 'face_value')
    def _compute_qty(self):
        for rec in self:
            rec.qty_faces = rec.carnet_qty * (rec.face_count or 0)
            rec.amount_total = rec.qty_faces * (rec.face_value or 0)

    @api.constrains('carnet_qty')
    def _check_carnet_qty(self):
        for rec in self:
            if rec.carnet_qty <= 0:
                raise ValidationError(
                    _('Le nombre de carnets à transférer doit être strictement positif.')
                )
