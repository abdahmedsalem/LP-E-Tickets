import os
from unittest.mock import patch

from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestMobileSecurityReadiness(TransactionCase):

    def setUp(self):
        super().setUp()
        self.readiness = self.env['acpec.mobile.security.readiness'].sudo()
        self.settings = self.env['acpec.mobile.security.setting'].sudo()
        self.keys = [
            'acpec_mobile_auth.otp_dev_mode',
            'acpec_mobile_auth.otp_request_cooldown_seconds',
            'acpec_mobile_auth.otp_limit_identifier_per_minute',
            'acpec_mobile_auth.otp_limit_identifier_per_day',
            'acpec_mobile_auth.otp_limit_ip_per_hour',
            'acpec_mobile_auth.otp_limit_register_ip_per_day',
        ]
        self.settings.search([('key', 'in', self.keys)]).unlink()

    def _runtime_env(self, acpec_env, dev_mode='', legacy_test_mode=''):
        return {
            'ACPEC_ENV': acpec_env,
            'ODOO_ENV': '',
            'ENV': '',
            'ACPEC_FUELTOKEN_DEV_MODE': dev_mode,
            'ACPEC_FUELTOKEN_TEST_MODE': legacy_test_mode,
        }

    def _sms_env(self, validation_key='', token='', provider='chinguisoft', url=''):
        return {
            'SMS_PROVIDER': provider,
            'SMS_URL': url,
            'CHINGUISOFT_URL': '',
            'SMS_VALIDATION_KEY': validation_key,
            'CHINGUI_SOFT_VALIDATION_KEY': '',
            'CHINGUISOFT_VALIDATION_KEY': '',
            'SMS_TOKEN': token,
            'CHINGUI_SOFT_TOKEN': '',
            'CHINGUISOFT_TOKEN': '',
        }

    def _set_setting(self, key, value):
        self.settings.search([('key', '=', key)]).unlink()
        return self.settings.create({
            'key': key,
            'value': str(value),
            'active': True,
        })

    def _codes(self, result):
        return {issue['code'] for issue in result['issues']}

    def _check(self, env):
        # Odoo tests run with --test-enable. Patch36A readiness must still be
        # testable for simulated production/dev runtime values.
        with patch.dict(os.environ, env, clear=False), patch(
            'odoo.addons.acpec_mobile_auth.models.mobile_security_policy.config',
            {'test_enable': False},
        ):
            return self.readiness.check_mobile_security_readiness()

    def test_dev_gate_allows_zero_antiflood_without_sms_readiness_failure(self):
        self._set_setting('acpec_mobile_auth.otp_request_cooldown_seconds', '0')

        env = {}
        env.update(self._runtime_env('dev', dev_mode='1'))
        env.update(self._sms_env())
        result = self._check(env)

        self.assertFalse(result['production'])
        self.assertEqual(result['runtime_env_label'], 'DEV_LIKE')
        self.assertTrue(result['runtime_dev_relax'])
        self.assertTrue(result['ready'])
        self.assertFalse(result['issues'])

    def test_legacy_otp_dev_setting_is_reported_as_critical(self):
        self._set_setting('acpec_mobile_auth.otp_dev_mode', 'True')

        env = {}
        env.update(self._runtime_env('dev', dev_mode='1'))
        env.update(self._sms_env())
        result = self._check(env)

        self.assertFalse(result['ready'])
        self.assertIn('OTP_DEV_MODE_LEGACY_SETTING_ENABLED', self._codes(result))

    def test_production_rejects_configured_zero_antiflood_values_before_safe_fallback(self):
        for key in self.keys[1:]:
            self._set_setting(key, '0')

        env = {}
        env.update(self._runtime_env('production'))
        env.update(self._sms_env(validation_key='validation-key', token='sms-token'))
        result = self._check(env)

        codes = self._codes(result)
        self.assertFalse(result['ready'])
        self.assertIn('OTP_REQUEST_COOLDOWN_ZERO', codes)
        self.assertIn('OTP_IDENTIFIER_PER_MINUTE_ZERO', codes)
        self.assertIn('OTP_IDENTIFIER_PER_DAY_ZERO', codes)
        self.assertIn('OTP_IP_PER_HOUR_ZERO', codes)
        self.assertIn('OTP_REGISTER_IP_PER_DAY_ZERO', codes)

    def test_production_chinguisoft_requires_secret_configuration(self):
        env = {}
        env.update(self._runtime_env('production'))
        env.update(self._sms_env())
        result = self._check(env)

        codes = self._codes(result)
        self.assertIn('SMS_VALIDATION_KEY_MISSING', codes)
        self.assertIn('SMS_TOKEN_MISSING', codes)
        self.assertNotIn('SMS_URL_MISSING', codes)
        self.assertFalse(result['ready'])

    def test_production_sms_env_aliases_are_accepted(self):
        env = self._runtime_env('production')
        env.update(self._sms_env())
        env.update({
            'CHINGUI_SOFT_VALIDATION_KEY': 'validation-key-from-env',
            'CHINGUI_SOFT_TOKEN': 'sms-token-from-env',
        })
        result = self._check(env)

        self.assertTrue(result['production'])
        self.assertTrue(result['ready'])
        self.assertFalse(result['issues'])

    def test_ready_when_production_configuration_is_safe(self):
        self._set_setting('acpec_mobile_auth.otp_request_cooldown_seconds', '60')
        self._set_setting('acpec_mobile_auth.otp_limit_identifier_per_minute', '1')
        self._set_setting('acpec_mobile_auth.otp_limit_identifier_per_day', '10')
        self._set_setting('acpec_mobile_auth.otp_limit_ip_per_hour', '30')
        self._set_setting('acpec_mobile_auth.otp_limit_register_ip_per_day', '100')

        env = {}
        env.update(self._runtime_env('production'))
        env.update(self._sms_env(validation_key='validation-key', token='sms-token'))
        result = self._check(env)

        self.assertTrue(result['production'])
        self.assertTrue(result['ready'])
        self.assertFalse(result['issues'])
