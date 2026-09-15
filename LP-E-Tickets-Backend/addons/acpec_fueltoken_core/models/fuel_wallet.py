from psycopg2 import IntegrityError

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
    qr_max_amount = fields.Monetary(string='Plafond QR client', default=5000, required=True)
    balance = fields.Monetary(string='Solde disponible', compute='_compute_quantities', store=False)
    qty_available = fields.Integer(string='Tickets disponibles', compute='_compute_quantities', store=False)
    qty_qr_active = fields.Integer(string='Tickets en QR actif', compute='_compute_quantities', store=False)
    qty_qr_blocked = fields.Integer(string='Tickets en QR bloqué', compute='_compute_quantities', store=False)
    qty_consumed = fields.Integer(string='Tickets consommés', compute='_compute_quantities', store=False)
    qty_expired = fields.Integer(string='Tickets expirés', compute='_compute_quantities', store=False)
    qty_transferred_out = fields.Integer(string='Tickets transférés', compute='_compute_quantities', store=False)
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

    @api.model
    def _wallet_internal_context_is_valid(self, operation):
        return (
            self.env.su
            and self.env.context.get(
                'acpec_fueltoken_wallet_internal_operation'
            ) == operation
        )

    @api.model
    def _create_internal(self, vals):
        return self.sudo().with_context(
            acpec_fueltoken_wallet_internal_operation='create',
        ).create(vals)

    def _write_internal(self, vals):
        return self.sudo().with_context(
            acpec_fueltoken_wallet_internal_operation='write',
        ).write(vals)

    def _purge_internal(self):
        return self.sudo().with_context(
            acpec_fueltoken_wallet_internal_operation='purge',
        ).unlink()

    @api.model_create_multi
    def create(self, vals_list):
        if not self._wallet_internal_context_is_valid('create'):
            raise UserError(_(
                'La création de comptes Tickets Carburant est réservée '
                'aux flux métier internes contrôlés.'
            ))
        return super().create(vals_list)

    def unlink(self):
        if not self._wallet_internal_context_is_valid('purge'):
            raise UserError(_(
                'Les comptes Tickets Carburant ne peuvent pas être supprimés '
                'hors flux interne contrôlé.'
            ))

        wallet_ids = self.ids
        if wallet_ids:
            has_face_lines = self.env[
                'acpec.fuel.face.line'
            ].sudo().search_count([
                ('wallet_id', 'in', wallet_ids),
            ])
            has_qrs = self.env['acpec.fuel.qr'].sudo().search_count([
                ('wallet_id', 'in', wallet_ids),
            ])
            if has_face_lines or has_qrs:
                raise UserError(_(
                    'Un compte Tickets Carburant contenant des carnets '
                    'ou des QR ne peut pas être purgé.'
                ))

        return super().unlink()

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
        partner = partner.sudo().exists() if partner else self.env['res.partner']
        company = company.sudo().exists() if company else self.env['res.company']

        if len(partner) != 1:
            raise ValidationError(_('Un seul partenaire est requis pour créer le compte Tickets Carburant.'))
        if len(company) != 1:
            raise ValidationError(_('Une seule société est requise pour créer le compte Tickets Carburant.'))

        Wallet = self.sudo()
        domain = [
            ('partner_id', '=', partner.id),
            ('company_id', '=', company.id),
        ]

        wallet = Wallet.search(domain, limit=1)
        if wallet:
            return wallet

        try:
            with self.env.cr.savepoint():
                return Wallet._create_internal({
                    'partner_id': partner.id,
                    'company_id': company.id,
                })
        except IntegrityError as error:
            if getattr(error.diag, 'constraint_name', False) != 'acpec_fuel_wallet_partner_company_unique':
                raise
            wallet = Wallet.search(domain, limit=1)
            if wallet:
                return wallet
            raise

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
        if not getattr(user, 'acpec_mobile_only', False):
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

    def _check_wallet_economic_identity_write_allowed(self, vals):
        protected_fields = {'partner_id', 'company_id'} & set(vals or {})
        if not protected_fields:
            return True

        for rec in self:
            for field_name in protected_fields:
                current_record = rec[field_name]
                current_id = current_record.id if current_record else False
                new_value = vals.get(field_name)
                new_id = new_value.id if hasattr(new_value, 'id') else new_value

                if new_id == current_id:
                    continue

                raise ValidationError(_(
                    "L'identité économique d'un compte Tickets Carburant "
                    "(client/société) ne peut pas être modifiée après création."
                ))
        return True

    def write(self, vals):
        if not self._wallet_internal_context_is_valid('write'):
            raise UserError(_(
                'La modification des comptes Tickets Carburant est réservée '
                'aux flux métier internes contrôlés.'
            ))
        if 'balance' in vals:
            raise UserError(_(
                'Le solde Tickets Carburant est calculé '
                'et ne peut pas être modifié directement.'
            ))
        self._check_wallet_economic_identity_write_allowed(vals)
        return super().write(vals)
