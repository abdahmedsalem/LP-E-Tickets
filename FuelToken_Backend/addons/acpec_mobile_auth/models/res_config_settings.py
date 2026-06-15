from odoo import fields, models


class ResConfigSettings(models.TransientModel):
    _inherit = 'res.config.settings'

    # Compatibility field referenced by a settings view loaded in Odoo.
    color_brand_light = fields.Char(
        string='Brand Light Color',
        config_parameter='muk_web_colors.color_brand_light',
    )
