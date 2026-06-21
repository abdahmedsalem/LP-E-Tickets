import os
from unittest.mock import patch

from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestMobileSecurityReadiness(TransactionCase):

    def setUp(self):
        super().setUp()
        self.readiness = self.env['acpec.mobile.security.readiness'].sudo()
        self.settings = self.env['acpec.mobile.security.setting'].sudo()
        self.icp = self.env['ir.config_parameter'].sudo()
        self.keys = [
            'acpec_mobile_auth.otp_dev_mode',
            'acpec_mobile_auth.otp_request_cooldown_seconds',
            'acpec_mobile_auth.otp_limit_identifier_per_minute',
            'acpec_mobile_auth.otp_limit_identifier_per_day',
            'acpec_mobile_auth.otp_limit_ip_per_hour',
            'acpec_mobile_auth.otp_limit_register_ip_per_day',
        ]
        self.settings.search([('key', 'in', self.keys)]).unlink()
        self._clear_sms_icp()

    def _runtime_env(self, acpec_env, test_mode=''):
        return {
            'ACPEC_ENV': acpec_env,
            'ODOO_ENV': '',
            'ENV': '',
            'ACPEC_FUELTOKEN_TEST_MODE': test_mode,
        }

    def _sms_env(self):
        return {
            'SMS_PROVIDER': '',
            'SMS_URL': '',
            'CHINGUISOFT_URL': '',
            'SMS_VALIDATION_KEY': '',
            'CHINGUI_SOFT_VALIDATION_KEY': '',
            'CHINGUISOFT_VALIDATION_KEY': '',
            'SMS_TOKEN': '',
            'CHINGUI_SOFT_TOKEN': '',
            'CHINGUISOFT_TOKEN': '',
        }

    def _clear_sms_icp(self):
        self.icp.set_param('SMS_PROVIDER', '')
        self.icp.set_param('SMS_URL', '')
        self.icp.set_param('SMS_VALIDATION_KEY', '')
        self.icp.set_param('SMS_TOKEN', '')

    def _set_setting(self, key, value):
        self.settings.search([('key', '=', key)]).unlink()
        return self.settings.create({
            'key': key,
            'value': str(value),
            'active': True,
        })

    def _codes(self, result):
        return {issue['code'] for issue in result['issues']}

    def test_non_production_allows_dev_values_without_critical_readiness_failure(self):
        self._set_setting('acpec_mobile_auth.otp_dev_mode', 'True')
        self._set_setting('acpec_mobile_auth.otp_request_cooldown_seconds', '0')

        env = {}
        env.update(self._runtime_env('dev', test_mode='1'))
        env.update(self._sms_env())
        with patch.dict(os.environ, env, clear=False):
            result = self.readiness.check_mobile_security_readiness()

        self.assertFalse(result['production'])
        self.assertTrue(result['ready'])
        self.assertFalse(result['issues'])

    def test_production_rejects_configured_otp_dev_mode_even_if_runtime_gate_blocks_it(self):
        self._set_setting('acpec_mobile_auth.otp_dev_mode', 'True')
        self.icp.set_param('SMS_PROVIDER', 'chinguisoft')
        self.icp.set_param('SMS_VALIDATION_KEY', 'validation-key')
        self.icp.set_param('SMS_TOKEN', 'sms-token')

        with patch.dict(os.environ, self._runtime_env('production'), clear=False):
            result = self.readiness.check_mobile_security_readiness()

        self.assertTrue(result['production'])
        self.assertFalse(result['ready'])
        self.assertIn('OTP_DEV_MODE_ENABLED_IN_PRODUCTION', self._codes(result))

    def test_production_rejects_configured_zero_antiflood_values_before_safe_fallback(self):
        self._set_setting('acpec_mobile_auth.otp_dev_mode', 'False')
        for key in self.keys[1:]:
            self._set_setting(key, '0')
        self.icp.set_param('SMS_PROVIDER', 'chinguisoft')
        self.icp.set_param('SMS_VALIDATION_KEY', 'validation-key')
        self.icp.set_param('SMS_TOKEN', 'sms-token')

        with patch.dict(os.environ, self._runtime_env('production'), clear=False):
            result = self.readiness.check_mobile_security_readiness()

        codes = self._codes(result)
        self.assertFalse(result['ready'])
        self.assertIn('OTP_REQUEST_COOLDOWN_ZERO', codes)
        self.assertIn('OTP_IDENTIFIER_PER_MINUTE_ZERO', codes)
        self.assertIn('OTP_IDENTIFIER_PER_DAY_ZERO', codes)
        self.assertIn('OTP_IP_PER_HOUR_ZERO', codes)
        self.assertIn('OTP_REGISTER_IP_PER_DAY_ZERO', codes)

    def test_production_chinguisoft_requires_secret_configuration(self):
        self.icp.set_param('SMS_PROVIDER', 'chinguisoft')
        self.icp.set_param('SMS_URL', '')
        self.icp.set_param('SMS_VALIDATION_KEY', '')
        self.icp.set_param('SMS_TOKEN', '')

        env = {}
        env.update(self._runtime_env('production'))
        env.update(self._sms_env())
        with patch.dict(os.environ, env, clear=False):
            result = self.readiness.check_mobile_security_readiness()

        codes = self._codes(result)
        self.assertIn('SMS_VALIDATION_KEY_MISSING', codes)
        self.assertIn('SMS_TOKEN_MISSING', codes)
        self.assertNotIn('SMS_URL_MISSING', codes)
        self.assertFalse(result['ready'])

    def test_production_sms_env_aliases_are_accepted(self):
        self.icp.set_param('SMS_PROVIDER', 'chinguisoft')
        self.icp.set_param('SMS_VALIDATION_KEY', '')
        self.icp.set_param('SMS_TOKEN', '')

        env = self._runtime_env('production')
        env.update({
            'CHINGUI_SOFT_VALIDATION_KEY': 'validation-key-from-env',
            'CHINGUI_SOFT_TOKEN': 'sms-token-from-env',
        })
        with patch.dict(os.environ, env, clear=False):
            result = self.readiness.check_mobile_security_readiness()

        self.assertTrue(result['production'])
        self.assertTrue(result['ready'])
        self.assertFalse(result['issues'])

    def test_ready_when_production_configuration_is_safe(self):
        self._set_setting('acpec_mobile_auth.otp_dev_mode', 'False')
        self._set_setting('acpec_mobile_auth.otp_request_cooldown_seconds', '60')
        self._set_setting('acpec_mobile_auth.otp_limit_identifier_per_minute', '1')
        self._set_setting('acpec_mobile_auth.otp_limit_identifier_per_day', '10')
        self._set_setting('acpec_mobile_auth.otp_limit_ip_per_hour', '30')
        self._set_setting('acpec_mobile_auth.otp_limit_register_ip_per_day', '100')
        self.icp.set_param('SMS_PROVIDER', 'chinguisoft')
        self.icp.set_param('SMS_VALIDATION_KEY', 'validation-key')
        self.icp.set_param('SMS_TOKEN', 'sms-token')

        with patch.dict(os.environ, self._runtime_env('production'), clear=False):
            result = self.readiness.check_mobile_security_readiness()

        self.assertTrue(result['production'])
        self.assertTrue(result['ready'])
        self.assertFalse(result['issues'])
