import os
from unittest.mock import patch

from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestMobileSecuritySettingsTable(TransactionCase):

    def setUp(self):
        super().setUp()
        self.policy = self.env['acpec.mobile.security.policy'].sudo()
        self.settings = self.env['acpec.mobile.security.setting'].sudo()
        self.icp = self.env['ir.config_parameter'].sudo()

    def _clear_setting(self, key):
        self.settings.search([('key', '=', key)]).unlink()

    def test_dedicated_setting_overrides_icp_when_active(self):
        key = 'acpec_mobile_auth.access_token_minutes'
        self._clear_setting(key)
        self.icp.set_param(key, '11')

        self.assertEqual(self.policy.access_token_minutes(), 11)

        self.settings.create({
            'key': key,
            'value': '17',
            'active': True,
        })

        self.assertEqual(self.policy.access_token_minutes(), 17)

    def test_inactive_dedicated_setting_falls_back_to_icp(self):
        key = 'acpec_mobile_auth.access_token_minutes'
        self._clear_setting(key)
        self.icp.set_param(key, '12')
        self.settings.create({
            'key': key,
            'value': '17',
            'active': False,
        })

        self.assertEqual(self.policy.access_token_minutes(), 12)

    def test_invalid_active_dedicated_setting_falls_back_to_safe_default(self):
        key = 'acpec_mobile_auth.access_token_minutes'
        self._clear_setting(key)
        self.icp.set_param(key, '12')
        self.settings.create({
            'key': key,
            'value': 'not-an-int',
            'active': True,
        })

        self.assertEqual(self.policy.access_token_minutes(), 15)

    def test_refresh_token_grace_seconds_uses_policy_and_dedicated_setting(self):
        key = 'acpec_mobile_auth.refresh_token_grace_seconds'
        self._clear_setting(key)
        self.icp.set_param(key, '40')

        session_model = self.env['acpec.mobile.session'].sudo()
        self.assertEqual(self.policy.refresh_token_grace_seconds(), 40)
        self.assertEqual(session_model._refresh_token_grace_seconds(), 40)

        self.settings.create({
            'key': key,
            'value': '999',
            'active': True,
        })

        self.assertEqual(self.policy.refresh_token_grace_seconds(), 120)
        self.assertEqual(session_model._refresh_token_grace_seconds(), 120)

    def test_zero_antiflood_dedicated_setting_keeps_runtime_gate(self):
        key = 'acpec_mobile_auth.otp_limit_identifier_per_minute'
        self._clear_setting(key)
        self.icp.set_param(key, '99')
        self.settings.create({
            'key': key,
            'value': '0',
            'active': True,
        })

        with patch.dict(os.environ, {
            'ACPEC_ENV': 'prod',
            'ODOO_ENV': '',
            'ENV': '',
            'ACPEC_FUELTOKEN_TEST_MODE': '',
        }, clear=False):
            self.assertEqual(self.policy.otp_limit_identifier_per_minute(), 1)

        with patch.dict(os.environ, {
            'ACPEC_ENV': 'dev',
            'ODOO_ENV': '',
            'ENV': '',
            'ACPEC_FUELTOKEN_TEST_MODE': '1',
        }, clear=False):
            self.assertEqual(self.policy.otp_limit_identifier_per_minute(), 0)
