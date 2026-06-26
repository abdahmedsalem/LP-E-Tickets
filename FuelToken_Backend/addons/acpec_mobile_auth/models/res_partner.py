from odoo import fields, models


class ResPartner(models.Model):
    _inherit = 'res.partner'

    acpec_is_mobile_partner = fields.Boolean(
        string='Partenaire mobile',
        default=False,
        index=True,
        copy=False,
        readonly=True,
        help='Technical marker set when the partner is created/linked through an ACPEC mobile signup.',
    )
