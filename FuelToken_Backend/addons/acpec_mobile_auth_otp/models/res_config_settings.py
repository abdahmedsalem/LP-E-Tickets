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
