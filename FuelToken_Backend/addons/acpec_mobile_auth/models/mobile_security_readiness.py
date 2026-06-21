import os

from odoo import api, models


class AcpecMobileSecurityReadiness(models.AbstractModel):
    _name = 'acpec.mobile.security.readiness'
    _description = 'ACPEC Mobile Security Production Readiness Check'

    SMS_DEFAULT_URL = 'https://chinguisoft.com/api/sms/validation'

    @api.model
    def _is_truthy(self, value):
        return str(value or '').strip().lower() in ('1', 'true', 'yes', 'y', 'on')

    @api.model
    def _issue(self, code, severity, message, setting_key=False):
        return {
            'code': code,
            'severity': severity,
            'message': message,
            'setting_key': setting_key or False,
        }

    @api.model
    def _raw_setting(self, key):
        dedicated_value = self.env['acpec.mobile.security.setting'].sudo().get_active_value(key)
        if dedicated_value is not None:
            return dedicated_value
        return self.env['ir.config_parameter'].sudo().get_param(key)

    @api.model
    def _raw_bool(self, key, default=False):
        raw = self._raw_setting(key)
        if raw in (False, None, ''):
            return bool(default)
        return self._is_truthy(raw)

    @api.model
    def _raw_int(self, key):
        raw = self._raw_setting(key)
        if raw in (False, None, ''):
            return None
        try:
            return int(raw)
        except Exception:
            return None

    @api.model
    def _config_or_env(self, icp_key, env_keys, default=''):
        icp = self.env['ir.config_parameter'].sudo()
        value = icp.get_param(icp_key)
        if value:
            return str(value).strip()
        for env_key in env_keys:
            value = os.getenv(env_key)
            if value:
                return str(value).strip()
        return default

    @api.model
    def _resolved_sms_config(self):
        return {
            'provider': self._config_or_env(
                'SMS_PROVIDER',
                ['SMS_PROVIDER'],
                default='chinguisoft',
            ).lower(),
            'validation_key': self._config_or_env(
                'SMS_VALIDATION_KEY',
                ['SMS_VALIDATION_KEY', 'CHINGUI_SOFT_VALIDATION_KEY', 'CHINGUISOFT_VALIDATION_KEY'],
            ),
            'token': self._config_or_env(
                'SMS_TOKEN',
                ['SMS_TOKEN', 'CHINGUI_SOFT_TOKEN', 'CHINGUISOFT_TOKEN'],
            ),
            'base_url': self._config_or_env(
                'SMS_URL',
                ['SMS_URL', 'CHINGUISOFT_URL'],
                default=self.SMS_DEFAULT_URL,
            ),
        }

    @api.model
    def check_mobile_security_readiness(self):
        """Return production-readiness issues without changing configuration."""
        policy = self.env['acpec.mobile.security.policy'].sudo()
        issues = []

        production = policy.runtime_is_production()

        if production and self._raw_bool(policy.OTP_DEV_MODE_KEY, default=False):
            issues.append(self._issue(
                'OTP_DEV_MODE_ENABLED_IN_PRODUCTION',
                'critical',
                'Le mode OTP développeur est configuré actif en environnement production.',
                policy.OTP_DEV_MODE_KEY,
            ))

        antiflood_specs = [
            (
                'OTP_REQUEST_COOLDOWN_ZERO',
                policy.OTP_REQUEST_COOLDOWN_SECONDS[0],
                'Le délai minimum entre demandes OTP est configuré à zéro.',
            ),
            (
                'OTP_IDENTIFIER_PER_MINUTE_ZERO',
                policy.OTP_LIMIT_IDENTIFIER_PER_MINUTE[0],
                'La limite OTP par identifiant et par minute est configurée à zéro.',
            ),
            (
                'OTP_IDENTIFIER_PER_DAY_ZERO',
                policy.OTP_LIMIT_IDENTIFIER_PER_DAY[0],
                'La limite OTP par identifiant et par jour est configurée à zéro.',
            ),
            (
                'OTP_IP_PER_HOUR_ZERO',
                policy.OTP_LIMIT_IP_PER_HOUR[0],
                'La limite OTP par IP et par heure est configurée à zéro.',
            ),
            (
                'OTP_REGISTER_IP_PER_DAY_ZERO',
                policy.OTP_LIMIT_REGISTER_IP_PER_DAY[0],
                'La limite OTP inscription par IP et par jour est configurée à zéro.',
            ),
        ]

        for code, key, message in antiflood_specs:
            value = self._raw_int(key)
            if production and value is not None and value <= 0:
                issues.append(self._issue(code, 'critical', message, key))

        sms_config = self._resolved_sms_config()
        if production and sms_config['provider'] == 'chinguisoft':
            if not sms_config['base_url']:
                issues.append(self._issue(
                    'SMS_URL_MISSING',
                    'warning',
                    'Le fournisseur SMS Chinguisoft est actif mais l’URL SMS est vide.',
                    'SMS_URL',
                ))
            if not sms_config['validation_key']:
                issues.append(self._issue(
                    'SMS_VALIDATION_KEY_MISSING',
                    'critical',
                    'Le fournisseur SMS Chinguisoft est actif mais la clé de validation SMS est vide.',
                    'SMS_VALIDATION_KEY',
                ))
            if not sms_config['token']:
                issues.append(self._issue(
                    'SMS_TOKEN_MISSING',
                    'critical',
                    'Le fournisseur SMS Chinguisoft est actif mais le token SMS est vide.',
                    'SMS_TOKEN',
                ))

        return {
            'production': production,
            'ready': not any(issue['severity'] == 'critical' for issue in issues),
            'issues': issues,
        }
