import os
from unittest.mock import patch

from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestMobileSecuritySettingsTable(TransactionCase):

    def setUp(self):
        super().setUp()
        self.policy = self.env['acpec.mobile.security.policy'].sudo()
        self.settings = self.env['acpec.mobile.security.setting'].sudo()

    def _clear_setting(self, key):
        self.settings.search([('key', '=', key)]).unlink()

    def _set_setting(self, key, value, active=True):
        self._clear_setting(key)
        return self.settings.create({
            'key': key,
            'value': str(value),
            'active': active,
        })

    def test_default_is_used_when_no_dedicated_setting_exists(self):
        key = 'acpec_mobile_auth.access_token_minutes'
        self._clear_setting(key)

        self.assertEqual(self.policy.access_token_minutes(), 15)

    def test_active_dedicated_setting_is_used(self):
        key = 'acpec_mobile_auth.access_token_minutes'
        self._set_setting(key, '17')

        self.assertEqual(self.policy.access_token_minutes(), 17)

    def test_inactive_dedicated_setting_falls_back_to_safe_default(self):
        key = 'acpec_mobile_auth.access_token_minutes'
        self._set_setting(key, '17', active=False)

        self.assertEqual(self.policy.access_token_minutes(), 15)

    def test_invalid_active_dedicated_setting_falls_back_to_safe_default(self):
        key = 'acpec_mobile_auth.access_token_minutes'
        self._set_setting(key, 'not-an-int')

        self.assertEqual(self.policy.access_token_minutes(), 15)

    def test_refresh_token_grace_seconds_uses_policy_and_dedicated_setting(self):
        key = 'acpec_mobile_auth.refresh_token_grace_seconds'
        session_model = self.env['acpec.mobile.session'].sudo()

        self._set_setting(key, '40')
        self.assertEqual(self.policy.refresh_token_grace_seconds(), 40)
        self.assertEqual(session_model._refresh_token_grace_seconds(), 40)

        self._set_setting(key, '999')
        self.assertEqual(self.policy.refresh_token_grace_seconds(), 120)
        self.assertEqual(session_model._refresh_token_grace_seconds(), 120)

    def test_zero_antiflood_setting_keeps_runtime_gate(self):
        key = 'acpec_mobile_auth.otp_limit_identifier_per_minute'
        self._set_setting(key, '0')

        with patch.dict(os.environ, {
            'ACPEC_ENV': 'prod',
            'ODOO_ENV': '',
            'ENV': '',
            'ACPEC_FUELTOKEN_DEV_MODE': '',
            'ACPEC_FUELTOKEN_TEST_MODE': '',
        }, clear=False):
            self.assertEqual(self.policy.otp_limit_identifier_per_minute(), 1)

        with patch.dict(os.environ, {
            'ACPEC_ENV': 'dev',
            'ODOO_ENV': '',
            'ENV': '',
            'ACPEC_FUELTOKEN_DEV_MODE': '1',
            'ACPEC_FUELTOKEN_TEST_MODE': '',
        }, clear=False):
            self.assertEqual(self.policy.otp_limit_identifier_per_minute(), 0)
