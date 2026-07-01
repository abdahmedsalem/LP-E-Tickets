from odoo import api, fields, models


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
        ('acpec_mobile_auth.api_diagnostic_logging_enabled', 'Enable production-safe API diagnostic logging'),
        ('acpec_mobile_auth.api_diagnostic_logging_until', 'API diagnostic logging expiration datetime'),
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

    @api.model
    def _security_setting_keys(self):
        return [key for key, _label in self.SETTING_KEYS]

    @api.model
    def _migrate_from_ir_config_parameter(self):
        """Copy legacy ICP mobile security values into the dedicated table.

        This migration is intentionally non-destructive:
        - it copies only known mobile security keys;
        - it never overwrites an existing dedicated setting, active or inactive;
        - it never deletes the legacy ir.config_parameter values;
        - it does not migrate SMS_* secrets.
        """
        icp = self.env['ir.config_parameter'].sudo()
        migrated = 0

        for key in self._security_setting_keys():
            existing = self.sudo().search([('key', '=', key)], limit=1)
            if existing:
                continue

            value = icp.get_param(key)
            if value in (False, None, ''):
                continue

            self.sudo().create({
                'key': key,
                'value': str(value),
                'active': True,
                'note': 'Migrated from ir.config_parameter by Patch29C.',
            })
            migrated += 1

        return migrated
