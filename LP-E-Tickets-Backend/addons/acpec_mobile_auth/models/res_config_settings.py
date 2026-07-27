from odoo import fields, models


class ResConfigSettings(models.TransientModel):
    _inherit = 'res.config.settings'

    # Compatibility fields referenced by inherited settings views loaded in Odoo.
    # Do not use muk_web config keys: muk_web is no longer used in this project.
    color_brand_light = fields.Char(
        string='Brand Light Color',
        config_parameter='acpec_mobile_auth.color_brand_light',
    )
    color_primary_light = fields.Char(
        string='Primary Light Color',
        config_parameter='acpec_mobile_auth.color_primary_light',
    )
