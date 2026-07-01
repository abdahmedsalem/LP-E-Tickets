# -*- coding: utf-8 -*-
from datetime import timedelta

from odoo import fields
from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_mobile_auth.controllers.api_common import AcpecMobileAuthApiCommon


@tagged('post_install', '-at_install')
class TestMobileApiDiagnosticLogging(TransactionCase):
    """Production-safe diagnostic logging foundation."""

    def _controller(self):
        controller = AcpecMobileAuthApiCommon()
        controller._test_env = self.env
        return controller

    def _set_setting(self, key, value):
        Setting = self.env['acpec.mobile.security.setting'].sudo()
        record = Setting.search([('key', '=', key)], limit=1)
        vals = {
            'key': key,
            'value': str(value),
            'active': True,
            'note': 'test diagnostic logging',
        }
        if record:
            record.write(vals)
        else:
            Setting.create(vals)

    def test_j0_diagnostic_requires_enabled_and_future_until(self):
        controller = self._controller()
        enabled_key = controller.API_DIAGNOSTIC_LOGGING_ENABLED_KEY
        until_key = controller.API_DIAGNOSTIC_LOGGING_UNTIL_KEY

        self.assertFalse(controller._api_diagnostic_logging_status()['enabled'])

        self._set_setting(enabled_key, '1')
        status = controller._api_diagnostic_logging_status()
        self.assertFalse(status['enabled'])
        self.assertEqual(status['reason'], 'missing_until')

        expired = fields.Datetime.now() - timedelta(minutes=1)
        self._set_setting(until_key, fields.Datetime.to_string(expired))
        status = controller._api_diagnostic_logging_status()
        self.assertFalse(status['enabled'])
        self.assertEqual(status['reason'], 'expired')

        future = fields.Datetime.now() + timedelta(hours=1)
        self._set_setting(until_key, fields.Datetime.to_string(future))
        status = controller._api_diagnostic_logging_status()
        self.assertTrue(status['enabled'])
        self.assertEqual(status['reason'], 'active')

    def test_j0_diagnostic_payload_redacts_secrets_and_hashes_replay_values(self):
        controller = self._controller()
        payload = {
            'recipient_phone': '47123456',
            'action_code': '1234',
            'otp': '999999',
            'public_code': 'PUBLIC-QR-SECRET',
            'qr_numeric_code': '1111-2222-3333',
            'idempotency_key': 'idem-secret-key',
            'proof_data': 'BASE64-PAYMENT-PROOF',
            'lines': [{'face_line_id': 10, 'qty_tickets': 2}],
        }
        safe = controller._diagnostic_redact_for_log(payload)
        rendered = repr(safe)

        self.assertNotIn('1234', rendered)
        self.assertNotIn('999999', rendered)
        self.assertNotIn('PUBLIC-QR-SECRET', rendered)
        self.assertNotIn('1111-2222-3333', rendered)
        self.assertNotIn('idem-secret-key', rendered)
        self.assertNotIn('BASE64-PAYMENT-PROOF', rendered)
        self.assertNotIn('47123456', rendered)

        self.assertIn('47****56', rendered)
        self.assertIn('sha256_12', rendered)
        self.assertEqual(safe['action_code']['redacted'], True)
        self.assertEqual(safe['idempotency_key']['redacted'], True)
        self.assertEqual(safe['lines'][0]['qty_tickets'], '2')

    def test_j0_diagnostic_logs_in_out_are_noop_when_disabled_and_safe_when_enabled(self):
        controller = self._controller()
        self.assertFalse(controller._log_api_diagnostic_in('test.endpoint', {'action_code': '1234'}))
        self.assertFalse(controller._log_api_diagnostic_out('test.endpoint', {'ok': True}))

        controller._test_api_diagnostic_settings = {
            controller.API_DIAGNOSTIC_LOGGING_ENABLED_KEY: '1',
            controller.API_DIAGNOSTIC_LOGGING_UNTIL_KEY: fields.Datetime.to_string(fields.Datetime.now() + timedelta(hours=1)),
        }
        self.assertTrue(controller._log_api_diagnostic_in('test.endpoint', {'action_code': '1234'}))
        self.assertTrue(controller._log_api_diagnostic_out('test.endpoint', {'ok': True}))
