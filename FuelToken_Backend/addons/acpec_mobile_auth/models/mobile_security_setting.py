from odoo import fields, models


class AcpecMobileSecuritySetting(models.Model):
    _name = 'acpec.mobile.security.setting'
    _description = 'ACPEC Mobile Security Setting'
    _order = 'key'

    SETTING_KEYS = [
        ('acpec_mobile_auth.access_token_minutes', 'Access token duration, in minutes'),
        ('acpec_mobile_auth.refresh_token_days', 'Refresh token duration, in days'),
        ('acpec_mobile_auth.refresh_token_grace_seconds', 'Refresh token rotation grace, in seconds'),
        ('acpec_mobile_auth.mobile_pin_lock_seconds', 'Mobile action code lock duration, in seconds'),
        ('acpec_mobile_auth.mobile_pin_max_attempts', 'Mobile action code max attempts before lock'),
        ('acpec_mobile_auth.mobile_pin_hard_block_attempts', 'Mobile action code hard block attempts'),
        ('acpec_mobile_auth.otp_code_length', 'OTP code length'),
        ('acpec_mobile_auth.otp_expiration_minutes', 'OTP expiration, in minutes'),
        ('acpec_mobile_auth.otp_max_attempts', 'OTP max attempts'),
        ('acpec_mobile_auth.otp_request_cooldown_seconds', 'OTP request cooldown, in seconds'),
        ('acpec_mobile_auth.otp_limit_identifier_per_minute', 'OTP limit per identifier per minute'),
        ('acpec_mobile_auth.otp_limit_identifier_per_day', 'OTP limit per identifier per day'),
        ('acpec_mobile_auth.otp_limit_ip_per_hour', 'OTP limit per IP per hour'),
        ('acpec_mobile_auth.otp_limit_register_ip_per_day', 'Registration OTP limit per IP per day'),
        ('acpec_mobile_auth.otp_dev_mode', 'OTP dev mode database flag'),
    ]

    key = fields.Selection(
        selection=SETTING_KEYS,
        required=True,
        index=True,
        copy=False,
    )
    value = fields.Char(required=True, copy=False)
    active = fields.Boolean(default=True, index=True)
    note = fields.Text(copy=False)

    _key_unique = models.Constraint(
        'UNIQUE(key)',
        'A mobile security setting key can only be defined once.',
    )

    def get_active_value(self, key):
        record = self.sudo().search([
            ('key', '=', key),
            ('active', '=', True),
        ], limit=1)
        if not record:
            return None
        return record.value if record.value not in (False, None) else ''
