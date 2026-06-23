import secrets

from odoo import api, fields, models, _
from odoo.exceptions import ValidationError
from odoo.tools import float_compare


class AcpecFuelFaceLine(models.Model):
    _name = 'acpec.fuel.face.line'
    _description = 'Carnet de tickets'
    _order = 'expires_at, lot_short_code, carnet_sequence, id'

    wallet_id = fields.Many2one('acpec.fuel.wallet', string='Compte Tickets Carburant', required=True, index=True, ondelete='restrict')
    partner_id = fields.Many2one('res.partner', related='wallet_id.partner_id', store=True, readonly=True, index=True)
    company_id = fields.Many2one('res.company', related='wallet_id.company_id', store=True, readonly=True, index=True)
    currency_id = fields.Many2one('res.currency', related='wallet_id.currency_id', store=True, readonly=True)
    purchase_id = fields.Many2one('acpec.fuel.purchase', string='Lot d\'achat', required=True, index=True, ondelete='restrict')
    purchase_line_id = fields.Many2one('acpec.fuel.purchase.line', string='Ligne d\'achat', required=True, index=True, ondelete='restrict')
    carnet_type_id = fields.Many2one('acpec.fuel.carnet.type', string='Type de carnet', required=True, index=True)
    face_value = fields.Monetary(string='Valeur de face', required=True)
    qty_initial = fields.Integer(string='Quantite initiale', required=True)
    qty_available = fields.Integer(string='Disponible', default=0)
    qty_qr_active = fields.Integer(string='En QR actif', default=0)
    qty_qr_blocked = fields.Integer(string='En QR bloque', default=0)
    qty_consumed = fields.Integer(string='Consommee', default=0)
    qty_expired = fields.Integer(string='Expiree', default=0)
    expires_at = fields.Datetime(string='Expiration')
    carnet_no = fields.Char(string='Reference complete carnet', index=True, copy=False, readonly=True)
    lot_short_code = fields.Char(string='Code court lot', index=True, copy=False, readonly=True)
    carnet_short_code = fields.Char(string='Code court carnet', index=True, copy=False, readonly=True)
    carnet_sequence = fields.Integer(string='Numero carnet', index=True, copy=False, readonly=True)
    amount_available = fields.Monetary(string='Montant disponible', compute='_compute_amounts')
    amount_total = fields.Monetary(string='Montant initial', compute='_compute_amounts')

    _carnet_no_unique = models.Constraint(
        'UNIQUE(company_id, carnet_no)',
        'La reference complete du carnet doit etre unique par societe.',
    )
    _carnet_short_code_unique = models.Constraint(
        'UNIQUE(company_id, carnet_short_code)',
        'Le code court du carnet doit etre unique par societe.',
    )

    def init(self):
        super().init()
        self.env.cr.execute("""
            SELECT conname
              FROM pg_constraint
             WHERE conrelid = 'acpec_fuel_face_line'::regclass
               AND contype = 'u'
               AND pg_get_constraintdef(oid) = 'UNIQUE (purchase_line_id, wallet_id)'
        """)
        for (constraint_name,) in self.env.cr.fetchall():
            safe_name = constraint_name.replace('"', '""')
            self.env.cr.execute(
                'ALTER TABLE acpec_fuel_face_line DROP CONSTRAINT IF EXISTS "%s"' % safe_name
            )

    @api.model
    def _generate_lot_short_code(self, company, size=5, max_attempts=100):
        alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
        domain_company = [('company_id', '=', company.id)] if company else []
        for _attempt in range(max_attempts):
            code = ''.join(secrets.choice(alphabet) for _ in range(size))
            if not self.sudo().search_count(domain_company + [('lot_short_code', '=', code)]):
                return code
        raise ValidationError(_('Impossible de generer un code court lot unique.'))

    @api.depends('face_value', 'qty_available', 'qty_initial')
    def _compute_amounts(self):
        for rec in self:
            rec.amount_available = rec.face_value * rec.qty_available
            rec.amount_total = rec.face_value * rec.qty_initial

    @api.constrains('qty_initial', 'qty_available', 'qty_qr_active', 'qty_qr_blocked', 'qty_consumed', 'qty_expired', 'face_value')
    def _check_quantities(self):
        for rec in self:
            quantities = [rec.qty_initial, rec.qty_available, rec.qty_qr_active, rec.qty_qr_blocked, rec.qty_consumed, rec.qty_expired]
            if any(qty < 0 for qty in quantities):
                raise ValidationError(_('Les quantites de faces ne peuvent pas etre negatives.'))
            if rec.face_value <= 0:
                raise ValidationError(_('La valeur de face doit etre positive.'))
            if rec.qty_initial != rec.qty_available + rec.qty_qr_active + rec.qty_qr_blocked + rec.qty_consumed + rec.qty_expired:
                raise ValidationError(_('Invariant de conservation des faces non respecte.'))

    def is_transferable_carnet_line(self):
        """Return True when the face line can be transferred as intact carnet blocks."""
        self.ensure_one()
        face_count = self.carnet_type_id.face_count or 0
        if face_count <= 0:
            return False
        if self.expires_at and self.expires_at <= fields.Datetime.now():
            return False
        if self.qty_initial <= 0 or self.qty_available <= 0:
            return False
        if self.qty_available != self.qty_initial:
            return False
        if self.qty_qr_active or self.qty_qr_blocked or self.qty_consumed or self.qty_expired:
            return False
        return self.qty_available >= face_count and self.qty_available % face_count == 0

    def transferable_carnet_count(self):
        self.ensure_one()
        if not self.is_transferable_carnet_line():
            return 0
        face_count = self.carnet_type_id.face_count or 0
        return self.qty_available // face_count

    def _lock_records(self):
        if not self.ids:
            return
        self.env.cr.execute('SELECT id FROM acpec_fuel_face_line WHERE id IN %s FOR UPDATE', [tuple(self.ids)])

    @api.model
    def reserve_available(self, wallet, requests):
        allocations = []
        now = fields.Datetime.now()
        has_explicit_requests = any(int(request.get('face_line_id') or 0) for request in requests)
        has_legacy_requests = any(not int(request.get('face_line_id') or 0) for request in requests)
        if has_explicit_requests and has_legacy_requests:
            raise ValidationError(_('Un QR ne peut pas melanger selection explicite de carnets et allocation automatique.'))

        seen_explicit_face_line_ids = set()
        for request in requests:
            requested_face_line_id = int(request.get('face_line_id') or 0)
            requested_face_value = request.get('face_value')
            requested_carnet_type_id = int(request.get('carnet_type_id') or 0)
            remaining = int(request['qty'])
            if remaining <= 0:
                raise ValidationError(_('La quantite a emettre doit etre positive.'))

            if requested_face_line_id:
                if requested_face_line_id in seen_explicit_face_line_ids:
                    raise ValidationError(_("Un carnet ne peut apparaitre qu'une seule fois dans un meme QR."))
                seen_explicit_face_line_ids.add(requested_face_line_id)

                self.env.cr.execute(
                    """
                    SELECT id
                      FROM acpec_fuel_face_line
                     WHERE id = %s
                       AND wallet_id = %s
                     FOR UPDATE
                    """,
                    (requested_face_line_id, wallet.id),
                )
                row = self.env.cr.fetchone()
                if not row:
                    raise ValidationError(_('Carnet indisponible ou non autorise.'))

                line = self.sudo().browse(row[0]).exists()
                line.invalidate_recordset(['qty_available', 'qty_qr_active', 'expires_at'])
                if not line:
                    raise ValidationError(_('Carnet indisponible ou non autorise.'))
                if line.company_id != wallet.company_id:
                    raise ValidationError(_('Carnet indisponible ou non autorise.'))
                if line.expires_at and line.expires_at <= now:
                    raise ValidationError(_('Carnet expire.'))
                if line.qty_available < remaining:
                    label = line.carnet_short_code or line.carnet_no or line.id
                    raise ValidationError(_('Quantite disponible insuffisante pour %s.') % label)

                line.write({
                    'qty_available': line.qty_available - remaining,
                    'qty_qr_active': line.qty_qr_active + remaining,
                })
                allocations.append({'face_line': line, 'qty': remaining})
                continue

            if not requested_carnet_type_id and requested_face_value is None:
                raise ValidationError(_('Chaque ligne doit contenir face_line_id, carnet_type_id ou face_value.'))

            if requested_carnet_type_id:
                self.env.cr.execute(
                    """
                    SELECT id
                      FROM acpec_fuel_face_line
                     WHERE wallet_id = %s
                       AND carnet_type_id = %s
                       AND qty_available > 0
                       AND (expires_at IS NULL OR expires_at > %s)
                     ORDER BY expires_at NULLS LAST, id
                     FOR UPDATE
                    """,
                    (wallet.id, requested_carnet_type_id, now),
                )
            else:
                self.env.cr.execute(
                    """
                    SELECT id
                      FROM acpec_fuel_face_line
                     WHERE wallet_id = %s
                       AND face_value = %s
                       AND qty_available > 0
                       AND (expires_at IS NULL OR expires_at > %s)
                     ORDER BY expires_at NULLS LAST, id
                     FOR UPDATE
                    """,
                    (wallet.id, float(requested_face_value), now),
                )

            line_ids = [row[0] for row in self.env.cr.fetchall()]
            if not line_ids:
                label = requested_carnet_type_id if requested_carnet_type_id else requested_face_value
                raise ValidationError(_('Quantite disponible insuffisante pour %s.') % label)

            lines = self.sudo().browse(line_ids)
            lines.invalidate_recordset(['qty_available', 'qty_qr_active'])

            for line in lines:
                if remaining <= 0:
                    break
                if not requested_carnet_type_id and float_compare(
                    line.face_value,
                    float(requested_face_value),
                    precision_rounding=line.currency_id.rounding or wallet.currency_id.rounding,
                ) != 0:
                    continue
                qty = min(remaining, line.qty_available)
                line.write({
                    'qty_available': line.qty_available - qty,
                    'qty_qr_active': line.qty_qr_active + qty,
                })
                allocations.append({'face_line': line, 'qty': qty})
                remaining -= qty

            if remaining:
                label = requested_carnet_type_id if requested_carnet_type_id else requested_face_value
                raise ValidationError(_('Quantite disponible insuffisante pour %s.') % label)
        return allocations

    def move_available_to_expired(self):
        for rec in self:
            qty = rec.qty_available
            if qty > 0:
                rec.write({'qty_available': 0, 'qty_expired': rec.qty_expired + qty})

    @api.model
    def credit_transferred(self, dest_wallet, purchase_line, carnet_type, face_value, qty, expires_at):
        """Legacy helper kept for compatibility.

        Crédite dest_wallet de qty faces issues d'un transfert en créant ou
        réutilisant une face_line destination.

        Depuis Patch34C, les transferts de carnets intacts doivent déplacer la
        même face_line vers le wallet destinataire au lieu de créer une copie.
        Ne pas utiliser ce helper pour les transferts de carnets intacts.

        Cherche une face_line existante (purchase_line_id, wallet_id).
        Si elle existe, augmente qty_initial et qty_available.
        Sinon en crée une nouvelle.
        Retourne la face_line de destination.
        """
        self.env.cr.execute(
            """
            SELECT id
              FROM acpec_fuel_face_line
             WHERE wallet_id = %s
               AND purchase_line_id = %s
             FOR UPDATE
            """,
            (dest_wallet.id, purchase_line.id),
        )
        row = self.env.cr.fetchone()
        dest_face_line = self.sudo().browse(row[0]) if row else self.browse()
        if dest_face_line:
            dest_face_line.invalidate_recordset(['qty_initial', 'qty_available'])
            dest_face_line.write({
                'qty_initial': dest_face_line.qty_initial + qty,
                'qty_available': dest_face_line.qty_available + qty,
            })
        else:
            dest_face_line = self.sudo().create({
                'wallet_id': dest_wallet.id,
                'purchase_id': purchase_line.purchase_id.id,
                'purchase_line_id': purchase_line.id,
                'carnet_type_id': carnet_type.id,
                'face_value': face_value,
                'qty_initial': qty,
                'qty_available': qty,
                'expires_at': expires_at,
            })
        return dest_face_line
