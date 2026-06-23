import os
from unittest.mock import patch

from odoo.tests import TransactionCase, tagged

from odoo.addons.acpec_mobile_auth.controllers.api_common import AcpecMobileAuthApiCommon


@tagged('post_install', '-at_install')
class TestSecretLogHygiene(TransactionCase):

    def test_redact_for_log_masks_sensitive_dict_values(self):
        controller = AcpecMobileAuthApiCommon()
        payload = {
            'access_token': 'access-secret',
            'refresh_token': 'refresh-secret',
            'nested': {
                'secret_code': '1234',
                'action_code': '9876',
            },
            'safe': 'visible',
        }

        redacted = controller._redact_for_log(payload)

        self.assertEqual(redacted['access_token'], '***REDACTED***')
        self.assertEqual(redacted['refresh_token'], '***REDACTED***')
        self.assertEqual(redacted['nested']['secret_code'], '***REDACTED***')
        self.assertEqual(redacted['nested']['action_code'], '***REDACTED***')
        self.assertEqual(redacted['safe'], 'visible')

    def test_redact_for_log_masks_sensitive_inline_text(self):
        controller = AcpecMobileAuthApiCommon()
        message = (
            'access_token=ACCESS_SECRET_VALUE '
            'refresh_token=REFRESH_SECRET_VALUE '
            'secret_code=PIN_SECRET_VALUE '
            'Validation-token=SMS_TOKEN_SECRET_VALUE '
            'validation_key=SMS_KEY_SECRET_VALUE'
        )

        redacted = controller._redact_for_log(message)

        self.assertNotIn('ACCESS_SECRET_VALUE', redacted)
        self.assertNotIn('REFRESH_SECRET_VALUE', redacted)
        self.assertNotIn('PIN_SECRET_VALUE', redacted)
        self.assertNotIn('SMS_TOKEN_SECRET_VALUE', redacted)
        self.assertNotIn('SMS_KEY_SECRET_VALUE', redacted)
        self.assertIn('access_token=', redacted)
        self.assertIn('refresh_token=', redacted)
        self.assertIn('Validation-token=', redacted)
        self.assertIn('validation_key=', redacted)
        self.assertIn('***REDACTED***', redacted)

    def test_otp_dev_runtime_ignores_legacy_test_mode_in_production(self):
        policy = self.env['acpec.mobile.security.policy'].sudo()
        with patch.dict(os.environ, {
            'ACPEC_ENV': 'prod',
            'ODOO_ENV': '',
            'ENV': '',
            'ACPEC_FUELTOKEN_TEST_MODE': '1',
            'ACPEC_FUELTOKEN_DEV_MODE': '1',
        }, clear=False):
            self.assertFalse(policy.otp_dev_runtime_allowed())

    def test_otp_dev_runtime_allows_explicit_dev_gate(self):
        policy = self.env['acpec.mobile.security.policy'].sudo()
        with patch.dict(os.environ, {
            'ACPEC_ENV': 'dev',
            'ODOO_ENV': '',
            'ENV': '',
            'ACPEC_FUELTOKEN_TEST_MODE': '',
            'ACPEC_FUELTOKEN_DEV_MODE': '1',
        }, clear=False):
            self.assertTrue(policy.otp_dev_runtime_allowed())
