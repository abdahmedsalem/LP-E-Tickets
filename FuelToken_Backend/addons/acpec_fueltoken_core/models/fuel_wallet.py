from odoo import api, fields, models, _
from odoo.exceptions import UserError, ValidationError


class AcpecFuelWallet(models.Model):
    _name = 'acpec.fuel.wallet'
    _description = 'Compte Tickets Carburant calculé'
    _inherit = ['mail.thread', 'mail.activity.mixin']
    _order = 'partner_id'

    name = fields.Char(string='Nom', compute='_compute_name', store=True)
    partner_id = fields.Many2one('res.partner', string='Client', required=True, index=True)
    company_id = fields.Many2one('res.company', string='Société', required=True, default=lambda self: self.env.company, index=True)
    currency_id = fields.Many2one('res.currency', related='company_id.currency_id', store=True, readonly=True)
    balance = fields.Monetary(string='Solde disponible', compute='_compute_quantities', store=False)
    qty_available = fields.Integer(string='Tickets disponibles', compute='_compute_quantities', store=False)
    qty_qr_active = fields.Integer(string='Faces en QR actif', compute='_compute_quantities', store=False)
    qty_qr_blocked = fields.Integer(string='Faces en QR bloqué', compute='_compute_quantities', store=False)
    qty_consumed = fields.Integer(string='Faces consommées', compute='_compute_quantities', store=False)
    qty_expired = fields.Integer(string='Faces expirées', compute='_compute_quantities', store=False)
    qty_transferred_out = fields.Integer(string='Faces transférées sortantes', compute='_compute_quantities', store=False)
    amount_qr_active = fields.Monetary(string='Montant en QR actif', compute='_compute_quantities', store=False)
    amount_qr_blocked = fields.Monetary(string='Montant en QR bloqué', compute='_compute_quantities', store=False)
    amount_consumed = fields.Monetary(string='Montant consommé', compute='_compute_quantities', store=False)
    amount_expired = fields.Monetary(string='Montant expiré', compute='_compute_quantities', store=False)
    amount_transferred_out = fields.Monetary(string='Montant transféré sortant', compute='_compute_quantities', store=False)
    face_line_ids = fields.One2many('acpec.fuel.face.line', 'wallet_id', string='Carnets')

    _partner_company_unique = models.Constraint(
        'UNIQUE(partner_id, company_id)',
        'Un client ne peut avoir qu’un compte Tickets Carburant par société.',
    )

    @api.depends('partner_id', 'company_id')
    def _compute_name(self):
        for rec in self:
            rec.name = '%s - %s' % (rec.partner_id.display_name or '', rec.company_id.name or '')

    def _compute_quantities(self):
        fields_to_zero = [
            'balance',
            'qty_available',
            'qty_qr_active',
            'qty_qr_blocked',
            'qty_consumed',
            'qty_expired',
            'qty_transferred_out',
            'amount_qr_active',
            'amount_qr_blocked',
            'amount_consumed',
            'amount_expired',
            'amount_transferred_out',
        ]
        for rec in self:
            for fname in fields_to_zero:
                setattr(rec, fname, 0)

        if not self:
            return

        groups = self.env['acpec.fuel.face.line'].sudo()._read_group(
            [('wallet_id', 'in', self.ids)],
            ['wallet_id', 'face_value'],
            ['qty_available:sum', 'qty_qr_active:sum', 'qty_qr_blocked:sum', 'qty_consumed:sum', 'qty_expired:sum', 'qty_transferred_out:sum'],
        )
        by_wallet = {wallet.id: {
            'balance': 0,
            'qty_available': 0,
            'qty_qr_active': 0,
            'qty_qr_blocked': 0,
            'qty_consumed': 0,
            'qty_expired': 0,
            'qty_transferred_out': 0,
            'amount_qr_active': 0,
            'amount_qr_blocked': 0,
            'amount_consumed': 0,
            'amount_expired': 0,
            'amount_transferred_out': 0,
        } for wallet in self}

        for wallet, face_value, qty_available, qty_qr_active, qty_qr_blocked, qty_consumed, qty_expired, qty_transferred_out in groups:
            if not wallet:
                continue
            wallet_id = wallet.id
            if wallet_id not in by_wallet:
                continue
            face_value = face_value or 0
            qty_available = qty_available or 0
            qty_qr_active = qty_qr_active or 0
            qty_qr_blocked = qty_qr_blocked or 0
            qty_consumed = qty_consumed or 0
            qty_expired = qty_expired or 0
            qty_transferred_out = qty_transferred_out or 0
            values = by_wallet[wallet_id]
            values['qty_available'] += qty_available
            values['qty_qr_active'] += qty_qr_active
            values['qty_qr_blocked'] += qty_qr_blocked
            values['qty_consumed'] += qty_consumed
            values['qty_expired'] += qty_expired
            values['qty_transferred_out'] += qty_transferred_out
            values['balance'] += qty_available * face_value
            values['amount_qr_active'] += qty_qr_active * face_value
            values['amount_qr_blocked'] += qty_qr_blocked * face_value
            values['amount_consumed'] += qty_consumed * face_value
            values['amount_expired'] += qty_expired * face_value
            values['amount_transferred_out'] += qty_transferred_out * face_value

        for rec in self:
            for fname, value in by_wallet[rec.id].items():
                setattr(rec, fname, value)

    def get_or_create(self, partner, company):
        wallet = self.sudo().search([('partner_id', '=', partner.id), ('company_id', '=', company.id)], limit=1)
        if wallet:
            return wallet
        try:
            return self.sudo().create({'partner_id': partner.id, 'company_id': company.id})
        except Exception:
            # Deux requêtes simultanées peuvent avoir passé le search() avant que l'une n'insère.
            # La contrainte unique partner_company_unique lève une IntegrityError — on la gère
            # gracieusement en relisant le wallet désormais existant.
            self.env.cr.rollback()
            return self.sudo().search([('partner_id', '=', partner.id), ('company_id', '=', company.id)], limit=1)

    @api.model
    def _fueltoken_user_has_group_xmlid(self, user, xmlid):
        group = self.env.ref(xmlid, raise_if_not_found=False)
        if not user or not group:
            return False
        return group in user.sudo().group_ids

    @api.model
    def _fueltoken_is_operational_mobile_user(self, user):
        if not user or not user.exists():
            return False
        if not getattr(user, 'mobile_only', False):
            return False
        operational_xmlids = (
            'acpec_fueltoken_base.group_fuel_station',
            'acpec_fueltoken_base.group_fuel_manager',
        )
        return any(
            self._fueltoken_user_has_group_xmlid(user, xmlid)
            for xmlid in operational_xmlids
        )

    @api.model
    def _fueltoken_partner_has_non_empty_client_wallet(self, partner, company=False):
        # V1 definition: active fuel value exists when there are available
        # faces, QR-active faces, QR-blocked faces, or active/blocked QR.
        # Consumed/expired history is not a hard blocker.
        partner = partner.sudo().exists() if partner else self.env['res.partner']
        if not partner:
            return False

        line_domain = [('wallet_id.partner_id', '=', partner.id)]
        qr_domain = [('partner_id', '=', partner.id)]
        if company:
            line_domain.append(('wallet_id.company_id', '=', company.id))
            qr_domain.append(('company_id', '=', company.id))

        line_domain.extend([
            '|', '|',
            ('qty_available', '>', 0),
            ('qty_qr_active', '>', 0),
            ('qty_qr_blocked', '>', 0),
        ])
        if self.env['acpec.fuel.face.line'].sudo().search_count(line_domain):
            return True

        qr_domain.append(('state', 'in', ['active', 'blocked']))
        if self.env['acpec.fuel.qr'].sudo().search_count(qr_domain):
            return True

        return False

    @api.model
    def _assert_no_non_empty_client_wallet_for_operational_mobile_user(self, user, company=False):
        user = user.sudo().exists() if user else self.env['res.users']
        if not user:
            return True
        if not self._fueltoken_is_operational_mobile_user(user):
            return True
        if not user.partner_id:
            return True
        if not self._fueltoken_partner_has_non_empty_client_wallet(user.partner_id, company=company):
            return True
        raise ValidationError(_(
            'Séparation des rôles FuelToken : un utilisateur mobile station ou manager '
            'ne peut pas être lié à un partenaire dont la wallet Tickets Carburant est non vide.'
        ))

    @api.model
    def _assert_users_have_no_non_empty_client_wallet_for_operational_mobile_role(self, users, company=False):
        for user in users.sudo().exists():
            self._assert_no_non_empty_client_wallet_for_operational_mobile_user(user, company=company)
        return True

    def write(self, vals):
        if 'balance' in vals:
            raise UserError(_('Le solde Tickets Carburant est calculé et ne peut pas être modifié directement.'))
        return super().write(vals)
