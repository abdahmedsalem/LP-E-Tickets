from odoo import _, fields, models
from odoo.exceptions import UserError, ValidationError


class ResCompany(models.Model):
    _inherit = 'res.company'

    acpec_fueltoken_enabled = fields.Boolean(
        string='Tickets Carburant activé',
        default=False,
        help=(
            'Coche la société unique qui porte Tickets Carburant. '
            'La base Odoo peut être multi-société, mais FuelToken est mono-société.'
        ),
    )

    def init(self):
        super().init()
        self.env.cr.execute("""
            CREATE UNIQUE INDEX IF NOT EXISTS res_company_acpec_fueltoken_single_company_uniq
                ON res_company ((1))
             WHERE acpec_fueltoken_enabled IS TRUE
        """)

    def _fueltoken_companies(self, limit=None):
        return self.sudo().search(
            [('acpec_fueltoken_enabled', '=', True)],
            limit=limit,
        )

    def _fueltoken_company_count(self):
        return self.sudo().search_count([('acpec_fueltoken_enabled', '=', True)])

    def _fueltoken_company(self):
        companies = self._fueltoken_companies(limit=2)
        if len(companies) != 1:
            raise UserError(_(
                'Configuration Tickets Carburant invalide : exactement une société doit porter FuelToken.'
            ))
        return companies

    def _acpec_fueltoken_has_wallets(self):
        if not self:
            return False
        try:
            Wallet = self.env['acpec.fuel.wallet'].sudo()
        except KeyError:
            return False
        return bool(Wallet.search([('company_id', 'in', self.ids)], limit=1))

    def _acpec_fueltoken_has_active_mobile_users(self):
        if not self:
            return False
        Users = self.env['res.users'].sudo().with_context(active_test=False)
        if 'acpec_mobile_only' not in Users._fields:
            return False
        return bool(Users.search([
            ('active', '=', True),
            ('acpec_mobile_only', '=', True),
            '|',
            ('company_id', 'in', self.ids),
            ('company_ids', 'in', self.ids),
        ], limit=1))

    def _check_acpec_fueltoken_enabled_write_allowed(self, vals):
        if 'acpec_fueltoken_enabled' not in vals or vals.get('acpec_fueltoken_enabled'):
            return True

        companies = self.filtered(lambda company: company.acpec_fueltoken_enabled)
        if not companies:
            return True

        if companies._acpec_fueltoken_has_wallets():
            raise ValidationError(_(
                "Tickets Carburant ne peut pas être désactivé tant que des "
                "wallets FuelToken existent pour cette société."
            ))

        if companies._acpec_fueltoken_has_active_mobile_users():
            raise ValidationError(_(
                "Tickets Carburant ne peut pas être désactivé tant que des "
                "utilisateurs mobiles actifs sont rattachés à cette société."
            ))
        return True

    def write(self, vals):
        self._check_acpec_fueltoken_enabled_write_allowed(vals)
        return super().write(vals)
