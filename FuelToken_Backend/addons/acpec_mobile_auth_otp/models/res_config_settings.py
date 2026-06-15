from odoo import fields, models


class ResConfigSettings(models.TransientModel):
    _inherit = 'res.config.settings'

    sms_provider = fields.Selection(
        [('chinguisoft', 'Chinguisoft')],
        string='SMS Provider',
        default='chinguisoft',
        config_parameter='SMS_PROVIDER',
    )
    sms_validation_key = fields.Char(
        string='SMS Validation Key',
        config_parameter='SMS_VALIDATION_KEY',
    )
    sms_token = fields.Char(
        string='SMS Validation Token',
        config_parameter='SMS_TOKEN',
    )
    sms_url = fields.Char(
        string='SMS Base URL',
        default='https://chinguisoft.com/api/sms/validation',
        config_parameter='SMS_URL',
    )
    sms_default_lang = fields.Selection(
        [('fr', 'French'), ('ar', 'Arabic')],
        string='SMS Default Language',
        default='fr',
        config_parameter='SMS_DEFAULT_LANG',
    )

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

    otp_limit_identifier_per_minute = fields.Integer(
        string='OTP limit per number / minute',
        default=1,
        config_parameter='acpec_mobile_auth.otp_limit_identifier_per_minute',
    )
    otp_limit_identifier_per_day = fields.Integer(
        string='OTP limit per number / day',
        default=10,
        config_parameter='acpec_mobile_auth.otp_limit_identifier_per_day',
    )
    otp_limit_ip_per_hour = fields.Integer(
        string='OTP limit per IP / hour',
        default=30,
        config_parameter='acpec_mobile_auth.otp_limit_ip_per_hour',
    )
    otp_limit_register_ip_per_day = fields.Integer(
        string='Registration OTP limit per IP / day',
        default=100,
        config_parameter='acpec_mobile_auth.otp_limit_register_ip_per_day',
    )
