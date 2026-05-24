from odoo import fields, models


class ResCompany(models.Model):
    _inherit = 'res.company'

    acpec_mobile_auth_enabled = fields.Boolean(
        string='ACPEC Mobile Auth Enabled',
        default=False,
        help='Allow this company to appear in the mobile application and accept mobile account creation.'
    )
