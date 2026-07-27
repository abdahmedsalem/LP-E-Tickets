# -*- coding: utf-8 -*-
from unittest.mock import patch

from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_mobile_auth.controllers import api_common as api_common_module
from odoo.addons.acpec_mobile_auth.controllers.api_common import AcpecMobileAuthApiCommon


@tagged('post_install', '-at_install')
class TestMobileApiDiagnosticLogging(TransactionCase):
    """Debug-only diagnostic logging foundation."""

    def _controller(self):
        controller = AcpecMobileAuthApiCommon()
        controller._test_env = self.env
        return controller

    def test_j4_legacy_diagnostic_settings_are_removed(self):
        controller = self._controller()

        legacy_enabled = 'acpec_mobile_auth.' + 'api_diagnostic_' + 'logging_enabled'
        legacy_until = 'acpec_mobile_auth.' + 'api_diagnostic_' + 'logging_until'
        removed_attrs = [
            'API_DIAGNOSTIC_' + 'LOGGING_ENABLED_KEY',
            'API_DIAGNOSTIC_' + 'LOGGING_UNTIL_KEY',
            '_api_diagnostic_' + 'setting_value',
            '_api_diagnostic_' + 'logging_status',
        ]

        for attr_name in removed_attrs:
            self.assertFalse(hasattr(controller, attr_name), attr_name)

        key_field = self.env['acpec.mobile.security.setting']._fields['key']
        selection = key_field.selection
        if callable(selection):
            selection = selection(self.env['acpec.mobile.security.setting'])
        selection_keys = [item[0] for item in selection]

        self.assertNotIn(legacy_enabled, selection_keys)
        self.assertNotIn(legacy_until, selection_keys)

    def test_j4_diagnostic_payload_redacts_secrets_and_hashes_replay_values(self):
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

    def test_j4_diagnostic_in_out_are_debug_only_and_redacted(self):
        controller = self._controller()
        params = {
            'recipient_phone': '47123456',
            'action_code': '1234',
            'access_token': 'access-token-secret',
        }

        with patch.object(api_common_module._logger, 'isEnabledFor', return_value=False):
            self.assertFalse(controller._log_api_diagnostic_in('test.endpoint', params, operation='test_operation'))
            self.assertFalse(controller._log_api_diagnostic_out('test.endpoint', {'ok': True}, operation='test_operation'))

        with self.assertLogs(api_common_module._logger.name, level='DEBUG') as logs:
            self.assertTrue(controller._log_api_diagnostic_in('test.endpoint', params, operation='test_operation'))
            self.assertTrue(controller._log_api_diagnostic_out(
                'test.endpoint',
                {'ok': True, 'refresh_token': 'refresh-token-secret'},
                operation='test_operation',
            ))

        rendered = '\n'.join(logs.output)

        self.assertIn(controller.API_DIAGNOSTIC_MARKER_IN, rendered)
        self.assertIn(controller.API_DIAGNOSTIC_MARKER_OUT, rendered)
        self.assertIn('mode=debug', rendered)
        self.assertIn('endpoint=test.endpoint', rendered)
        self.assertIn('operation=test_operation', rendered)
        self.assertIn('method=', rendered)
        self.assertIn('path=', rendered)
        self.assertIn('db=', rendered)
        self.assertIn('uid=', rendered)
        self.assertIn('company_id=', rendered)

        self.assertNotIn('1234', rendered)
        self.assertNotIn('47123456', rendered)
        self.assertNotIn('access-token-secret', rendered)
        self.assertNotIn('refresh-token-secret', rendered)
        self.assertIn('47****56', rendered)

    def test_j4_refusal_marker_stays_structured_and_redacted(self):
        controller = self._controller()

        with self.assertLogs(api_common_module._logger.name, level='WARNING') as logs:
            self.assertTrue(controller._log_api_refusal_marker(
                'VALIDATION_ERROR',
                reason='action code rejected',
                params={
                    'action_code': '1234',
                    'recipient_phone': '47123456',
                },
                operation='test_operation',
                endpoint='test.endpoint',
                reference='SEC-TEST',
            ))

        rendered = '\n'.join(logs.output)
        self.assertIn(controller.API_DIAGNOSTIC_MARKER_REFUSED, rendered)
        self.assertIn('endpoint=test.endpoint', rendered)
        self.assertIn('operation=test_operation', rendered)
        self.assertIn('code=VALIDATION_ERROR', rendered)
        self.assertIn('reference=SEC-TEST', rendered)
        self.assertNotIn('1234', rendered)
        self.assertNotIn('47123456', rendered)
        self.assertIn('47****56', rendered)
