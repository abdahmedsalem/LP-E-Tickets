from odoo import fields, models


class ResConfigSettings(models.TransientModel):
    _inherit = 'res.config.settings'

    MOBILE_SECURITY_SETTING_KEYS = {
        'otp_limit_identifier_per_minute': 'acpec_mobile_auth.otp_limit_identifier_per_minute',
        'otp_limit_identifier_per_day': 'acpec_mobile_auth.otp_limit_identifier_per_day',
        'otp_limit_ip_per_hour': 'acpec_mobile_auth.otp_limit_ip_per_hour',
        'otp_limit_register_ip_per_day': 'acpec_mobile_auth.otp_limit_register_ip_per_day',
    }

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

    otp_limit_identifier_per_minute = fields.Integer(
        string='OTP limit per number / minute',
        default=1,
    )
    otp_limit_identifier_per_day = fields.Integer(
        string='OTP limit per number / day',
        default=10,
    )
    otp_limit_ip_per_hour = fields.Integer(
        string='OTP limit per IP / hour',
        default=30,
    )
    otp_limit_register_ip_per_day = fields.Integer(
        string='Registration OTP limit per IP / day',
        default=100,
    )

    def _get_mobile_security_setting_model(self):
        return self.env['acpec.mobile.security.setting'].sudo()

    def _get_mobile_security_policy(self):
        return self.env['acpec.mobile.security.policy'].sudo()

    def _set_mobile_security_value(self, key, value):
        settings = self._get_mobile_security_setting_model()
        record = settings.search([('key', '=', key)], limit=1)
        vals = {
            'key': key,
            'value': str(value if value not in (False, None, '') else 0),
            'active': True,
        }
        if record:
            record.write(vals)
        else:
            settings.create(vals)

    def get_values(self):
        res = super().get_values()
        policy = self._get_mobile_security_policy()
        res.update({
            'otp_limit_identifier_per_minute': policy.otp_limit_identifier_per_minute(),
            'otp_limit_identifier_per_day': policy.otp_limit_identifier_per_day(),
            'otp_limit_ip_per_hour': policy.otp_limit_ip_per_hour(),
            'otp_limit_register_ip_per_day': policy.otp_limit_register_ip_per_day(),
        })
        return res

    def set_values(self):
        super().set_values()
        for field_name, key in self.MOBILE_SECURITY_SETTING_KEYS.items():
            self._set_mobile_security_value(key, getattr(self, field_name))
