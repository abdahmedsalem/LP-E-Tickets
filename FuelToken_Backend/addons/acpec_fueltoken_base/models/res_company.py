from odoo import _, fields, models
from odoo.exceptions import UserError


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
