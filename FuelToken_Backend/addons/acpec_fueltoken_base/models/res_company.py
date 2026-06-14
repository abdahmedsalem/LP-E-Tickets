from odoo import fields, models


class ResCompany(models.Model):
    _inherit = 'res.company'

    acpec_fueltoken_enabled = fields.Boolean(string='Tickets Carburant activé', default=True)
