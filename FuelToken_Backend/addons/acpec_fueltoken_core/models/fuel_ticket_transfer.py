from odoo import api, fields, models, _
from odoo.exceptions import UserError, ValidationError


class AcpecFuelTicketTransfer(models.Model):
    _name = 'acpec.fuel.ticket.transfer'
    _description = 'Transfert de tickets'
    _inherit = ['mail.thread', 'mail.activity.mixin', 'acpec.fuel.public.code.mixin']
    _order = 'id desc'

    name = fields.Char(string='Référence interne', default='New', readonly=True, copy=False)
    source_wallet_id = fields.Many2one(
        'acpec.fuel.wallet', string='Compte source',
        required=True, index=True, ondelete='restrict', tracking=True,
    )
    source_partner_id = fields.Many2one(
        'res.partner', string='Partenaire source', related='source_wallet_id.partner_id',
        store=True, readonly=True, index=True,
    )
    dest_wallet_id = fields.Many2one(
        'acpec.fuel.wallet', string='Compte destinataire',
        required=True, index=True, ondelete='restrict', tracking=True,
    )
    dest_partner_id = fields.Many2one(
        'res.partner', string='Partenaire destinataire', related='dest_wallet_id.partner_id',
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
        'acpec.fuel.ticket.transfer.line', 'transfer_id', string='Lignes',
    )
    note = fields.Text(string='Motif / note')
    idempotency_key = fields.Char(string='Clé idempotence', index=True, copy=False)
    request_hash = fields.Char(string='Hash requête idempotence', index=True, copy=False)
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
        "Cette operation de transfert ticket a deja ete enregistree pour ce compte source.",
    )

    @api.model_create_multi
    def create(self, vals_list):
        if not self.env.context.get('allow_fuel_ticket_transfer_create'):
            raise UserError(_(
                'La création d un transfert de tickets est réservée au flux mobile backend contrôlé.'
            ))
        for vals in vals_list:
            if vals.get('name', 'New') == 'New':
                vals['name'] = (
                    self.env['ir.sequence'].next_by_code('acpec.fuel.ticket.transfer') or 'New'
                )
            if not vals.get('public_code'):
                vals['public_code'] = self._create_unique_public_code(prefix='TTF', size=18)
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
                raise ValidationError(_('Le compte source et le compte destinataire doivent être différents.'))
            if rec.source_wallet_id.company_id != rec.company_id:
                raise ValidationError(_('Le compte source doit appartenir à la même société que le transfert.'))
            if rec.dest_wallet_id.company_id != rec.company_id:
                raise ValidationError(_('Le compte destinataire doit appartenir à la même société que le transfert.'))

    def write(self, vals):
        if vals and not self.env.context.get('allow_fuel_ticket_transfer_update'):
            raise UserError(_(
                'Les transferts de tickets sont en lecture seule hors flux interne contrôlé.'
            ))
        return super().write(vals)

    def unlink(self):
        if not self.env.context.get('allow_fuel_ticket_transfer_unlink'):
            raise UserError(_(
                'Les transferts de tickets ne peuvent pas être supprimés hors flux interne contrôlé.'
            ))
        return super().unlink()

    def _prepare_fragment_identity_vals(self, source_face_line, transfer_line):
        self.ensure_one()
        FaceLine = self.env['acpec.fuel.face.line'].sudo()
        transfer_ref = (self.name or ('TTR-%s' % self.id)).replace('/', '-')
        carnet_no = '%s-F%03d' % (transfer_ref, transfer_line.id)
        return {
            'carnet_no': carnet_no,
            'lot_short_code': source_face_line.lot_short_code or FaceLine._generate_lot_short_code(self.company_id),
            'carnet_short_code': FaceLine._generate_carnet_short_code(self.company_id),
            'carnet_sequence': transfer_line.id,
        }

    def action_confirm(self, actor_user=None):
        """Confirme un transfert de tickets disponibles."""
        self.ensure_one()
        if self.state == 'confirmed':
            return True
        if not actor_user:
            if getattr(self.env, 'su', False):
                raise UserError(_('Acteur de confirmation requis.'))
            actor_user = self.env.user
        actor_user = self.env['res.users'].sudo().browse(
            actor_user.id if hasattr(actor_user, 'id') else int(actor_user or 0)
        ).exists()
        if not actor_user:
            raise UserError(_('Acteur de confirmation invalide.'))

        if self.state != 'draft':
            raise UserError(_('Seul un transfert ticket en brouillon peut être confirmé.'))
        if self.source_wallet_id == self.dest_wallet_id:
            raise ValidationError(_('Le compte source et le compte destinataire doivent être différents.'))
        if not self.line_ids:
            raise UserError(_('Le transfert ticket doit contenir au moins une ligne.'))

        FaceLine = self.env['acpec.fuel.face.line'].sudo()
        Tx = self.env['acpec.fuel.transaction'].sudo()
        now = fields.Datetime.now()

        with self.env.cr.savepoint():
            self.env.cr.execute(
                'SELECT id FROM acpec_fuel_wallet WHERE id IN %s FOR UPDATE',
                [tuple((self.source_wallet_id | self.dest_wallet_id).ids)],
            )
            src_face_line_ids = tuple(self.line_ids.mapped('source_face_line_id').ids)
            if not src_face_line_ids:
                raise ValidationError(_('Aucune ligne source valide dans le transfert ticket.'))
            self.env.cr.execute(
                'SELECT id FROM acpec_fuel_face_line WHERE id IN %s FOR UPDATE',
                [src_face_line_ids],
            )
            self.line_ids.mapped('source_face_line_id').invalidate_recordset()

            src_tx_lines = []
            dst_tx_lines = []

            for trf_line in self.line_ids:
                src_face_line = trf_line.source_face_line_id
                qty_to_transfer = int(trf_line.qty_faces or 0)

                if trf_line.dest_face_line_id:
                    continue
                if qty_to_transfer <= 0:
                    raise ValidationError(_('La quantité de tickets à transférer doit être strictement positive.'))
                if src_face_line.wallet_id != self.source_wallet_id:
                    raise ValidationError(_(
                        "La ligne '%s' n'appartient pas au compte source."
                    ) % (src_face_line.carnet_short_code or src_face_line.carnet_no or src_face_line.id))
                if src_face_line.company_id != self.company_id:
                    raise ValidationError(_('La ligne source doit appartenir à la même société que le transfert.'))
                if src_face_line.expires_at and src_face_line.expires_at <= now:
                    raise ValidationError(_(
                        "La ligne '%s' est expirée et ne peut pas être transférée."
                    ) % (src_face_line.carnet_short_code or src_face_line.carnet_no or src_face_line.id))
                if src_face_line.qty_available < qty_to_transfer:
                    raise ValidationError(_(
                        "Tickets disponibles insuffisants pour '%s' : %d disponibles, %d demandés."
                    ) % (
                        src_face_line.carnet_short_code or src_face_line.carnet_no or src_face_line.id,
                        src_face_line.qty_available,
                        qty_to_transfer,
                    ))

                identity_vals = self._prepare_fragment_identity_vals(src_face_line, trf_line)
                dest_face_line = FaceLine.with_context(allow_fuel_face_line_create=True).sudo().create(dict(identity_vals, **{
                    'wallet_id': self.dest_wallet_id.id,
                    'purchase_id': src_face_line.purchase_id.id,
                    'purchase_line_id': src_face_line.purchase_line_id.id,
                    'carnet_type_id': src_face_line.carnet_type_id.id,
                    'face_value': src_face_line.face_value,
                    'qty_initial': qty_to_transfer,
                    'qty_available': qty_to_transfer,
                    'expires_at': src_face_line.expires_at,
                    'origin_face_line_id': src_face_line.id,
                    'origin_ticket_transfer_line_id': trf_line.id,
                    'is_transfer_fragment': True,
                }))

                src_face_line.with_context(allow_fuel_face_line_state_update=True).write({
                    'qty_available': src_face_line.qty_available - qty_to_transfer,
                    'qty_transferred_out': src_face_line.qty_transferred_out + qty_to_transfer,
                })
                trf_line.sudo().with_context(allow_fuel_ticket_transfer_update=True).write({'dest_face_line_id': dest_face_line.id})

                src_tx_lines.append({
                    'face_line_id': src_face_line.id,
                    'purchase_id': src_face_line.purchase_id.id,
                    'purchase_line_id': src_face_line.purchase_line_id.id,
                    'ticket_transfer_id': self.id,
                    'face_value': src_face_line.face_value,
                    'qty': qty_to_transfer,
                })
                dst_tx_lines.append({
                    'face_line_id': dest_face_line.id,
                    'purchase_id': src_face_line.purchase_id.id,
                    'purchase_line_id': src_face_line.purchase_line_id.id,
                    'ticket_transfer_id': self.id,
                    'face_value': src_face_line.face_value,
                    'qty': qty_to_transfer,
                })

            counterparty_user = Tx._single_user_for_partner(self.dest_partner_id)
            note_text = (self.note or '').strip()
            outgoing_note = _('Transfert ticket sortant vers %s') % (self.dest_partner_id.display_name)
            incoming_note = _('Transfert ticket entrant de %s') % (self.source_partner_id.display_name)
            if note_text:
                outgoing_note = '%s. %s' % (outgoing_note, _('Motif : %s') % note_text)
                incoming_note = '%s. %s' % (incoming_note, _('Motif : %s') % note_text)

            if src_tx_lines:
                Tx.log(
                    'transfert_ticket', self.company_id,
                    wallet=self.source_wallet_id,
                    ticket_transfer=self,
                    lines=src_tx_lines,
                    note=outgoing_note,
                    transaction_effect='outgoing',
                    idempotency_key='SRC-TKT-%s' % (self.idempotency_key or str(self.id)),
                    request_hash=self.request_hash,
                    actor_partner=self.source_partner_id,
                    counterparty_partner=self.dest_partner_id,
                    counterparty_user=counterparty_user,
                )
                Tx.log(
                    'transfert_ticket', self.company_id,
                    wallet=self.dest_wallet_id,
                    ticket_transfer=self,
                    lines=dst_tx_lines,
                    note=incoming_note,
                    transaction_effect='incoming',
                    idempotency_key='DST-TKT-%s' % (self.idempotency_key or str(self.id)),
                    request_hash=self.request_hash,
                    actor_partner=self.source_partner_id,
                    counterparty_partner=self.dest_partner_id,
                    counterparty_user=counterparty_user,
                )

            self.with_context(allow_fuel_ticket_transfer_update=True).write({
                'state': 'confirmed',
                'confirmed_at': now,
                'confirmed_by': actor_user.id,
            })
        return True

    def action_cancel(self):
        self.ensure_one()
        if self.state == 'confirmed':
            raise UserError(_(
                "Un transfert ticket déjà confirmé ne peut pas être annulé. "
                "Créez un transfert inverse si nécessaire."
            ))
        self.with_context(allow_fuel_ticket_transfer_update=True).write({'state': 'cancelled'})
        return True


class AcpecFuelTicketTransferLine(models.Model):
    _name = 'acpec.fuel.ticket.transfer.line'
    _description = 'Ligne de transfert de tickets'
    _order = 'transfer_id, id'

    transfer_id = fields.Many2one(
        'acpec.fuel.ticket.transfer', string='Transfert ticket',
        required=True, ondelete='cascade', index=True,
    )
    company_id = fields.Many2one(
        'res.company', related='transfer_id.company_id', store=True, readonly=True,
    )
    currency_id = fields.Many2one(
        'res.currency', related='transfer_id.currency_id', store=True, readonly=True,
    )
    source_face_line_id = fields.Many2one(
        'acpec.fuel.face.line', string='Ligne source',
        required=True, index=True, ondelete='restrict',
    )
    dest_face_line_id = fields.Many2one(
        'acpec.fuel.face.line', string='Fragment destination',
        readonly=True, copy=False, index=True,
    )
    carnet_type_id = fields.Many2one(
        'acpec.fuel.carnet.type', related='source_face_line_id.carnet_type_id',
        store=True, readonly=True,
    )
    face_value = fields.Monetary(
        related='source_face_line_id.face_value', store=True, readonly=True,
    )
    qty_faces = fields.Integer(string='Tickets transférés', required=True)
    amount_total = fields.Monetary(
        string='Montant', compute='_compute_amount_total', store=True,
    )

    @api.model_create_multi
    def create(self, vals_list):
        if not self.env.context.get('allow_fuel_ticket_transfer_create'):
            raise UserError(_(
                'La création d une ligne de transfert de tickets est réservée au flux interne contrôlé.'
            ))
        return super().create(vals_list)

    @api.depends('qty_faces', 'face_value')
    def _compute_amount_total(self):
        for rec in self:
            rec.amount_total = (rec.qty_faces or 0) * (rec.face_value or 0)

    @api.constrains('qty_faces')
    def _check_qty_faces(self):
        for rec in self:
            if rec.qty_faces <= 0:
                raise ValidationError(_('Le nombre de tickets à transférer doit être strictement positif.'))

    def write(self, vals):
        if vals and not self.env.context.get('allow_fuel_ticket_transfer_update'):
            raise UserError(_(
                'Les lignes de transfert de tickets sont en lecture seule hors flux interne contrôlé.'
            ))
        return super().write(vals)

    def unlink(self):
        if not self.env.context.get('allow_fuel_ticket_transfer_unlink'):
            raise UserError(_(
                'Les lignes de transfert de tickets ne peuvent pas être supprimées hors flux interne contrôlé.'
            ))
        return super().unlink()
