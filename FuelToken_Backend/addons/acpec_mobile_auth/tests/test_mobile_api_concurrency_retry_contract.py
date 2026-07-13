# -*- coding: utf-8 -*-

import inspect
from types import SimpleNamespace
from unittest.mock import patch

from psycopg2 import errors as pg_errors

from odoo.exceptions import AccessError, ConcurrencyError, ValidationError
from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_mobile_auth.controllers.api_common import (
    AcpecMobileAuthApiCommon,
    MobileSensitiveActionError,
)
from odoo.addons.acpec_mobile_auth.exceptions import MobileSensitivePinBusy
from odoo.addons.acpec_mobile_auth.controllers.api_public import (
    AcpecMobileAuthApiPublic,
)


@tagged('post_install', '-at_install')
class TestMobileApiConcurrencyRetryContract(TransactionCase):

    def _controller(self):
        controller = AcpecMobileAuthApiCommon()
        controller._test_env = self.env
        controller._test_request_path = '/api/acpec/test/concurrency-retry'
        controller._test_request_ip = '10.0.0.24'
        controller._test_user_agent = 'patch43M24-B-test'
        return controller

    def test_retryable_concurrency_exceptions_are_reraised_by_default(self):
        controller = self._controller()
        exceptions = (
            pg_errors.LockNotAvailable('lock not available'),
            pg_errors.SerializationFailure('serialization failure'),
            pg_errors.DeadlockDetected('deadlock detected'),
            ConcurrencyError('odoo concurrency error'),
        )

        for exc in exceptions:
            with self.subTest(exception_type=type(exc).__name__):
                with self.assertRaises(type(exc)):
                    controller._handle_exception_response(
                        exc,
                        operation='retry_safe_test',
                    )

    def test_validation_error_keeps_mobile_error_contract(self):
        controller = self._controller()

        response = controller._handle_exception_response(
            ValidationError('validation test'),
            operation='validation_test',
        )

        self.assertFalse(response['ok'])
        self.assertEqual(response['error']['code'], 'VALIDATION_ERROR')

    def test_pin_busy_keeps_action_in_progress_without_count_or_retry(self):
        controller = self._controller()
        user = SimpleNamespace(
            acpec_mobile_pin_failed_count=3,
            acpec_mobile_pin_required=False,
            acpec_mobile_pin_set=True,
            acpec_mobile_pin_locked_until=False,
        )

        event_type, code, severity, failed_count_after = (
            controller._classify_pin_failure(
                MobileSensitivePinBusy('pin lock busy'),
                user,
                failed_count_before=3,
            )
        )

        self.assertEqual(event_type, 'sensitive_action_busy')
        self.assertEqual(code, 'ACTION_IN_PROGRESS')
        self.assertEqual(severity, 'warning')
        self.assertEqual(failed_count_after, 3)

        exc = MobileSensitiveActionError(
            code,
            'Une autre opération sensible est déjà en cours.',
            debug_reason='sensitive_action_busy',
            reference='SEC-PIN-BUSY-TEST',
        )
        with patch.object(controller, '_log_api_refusal_marker') as log_refusal:
            response = controller._handle_exception_response(
                exc,
                operation='pin_busy_test',
            )

        self.assertFalse(response['ok'])
        self.assertEqual(response['error']['code'], 'ACTION_IN_PROGRESS')
        self.assertEqual(
            response['error']['reference'],
            'SEC-PIN-BUSY-TEST',
        )
        log_refusal.assert_called_once()

    def test_wrong_pin_keeps_single_count_and_mobile_error_contract(self):
        controller = self._controller()
        user = SimpleNamespace(
            acpec_mobile_pin_failed_count=4,
            acpec_mobile_pin_required=False,
            acpec_mobile_pin_set=True,
            acpec_mobile_pin_locked_until=False,
        )

        event_type, code, severity, failed_count_after = (
            controller._classify_pin_failure(
                AccessError('invalid action code'),
                user,
                failed_count_before=3,
            )
        )

        self.assertEqual(event_type, 'invalid_action_code')
        self.assertEqual(code, 'INVALID_ACTION_CODE')
        self.assertEqual(severity, 'warning')
        self.assertEqual(failed_count_after, 4)

        exc = MobileSensitiveActionError(
            code,
            'Code d’action invalide.',
            debug_reason='invalid_action_code',
            reference='SEC-PIN-INVALID-TEST',
        )
        with patch.object(controller, '_log_api_refusal_marker') as log_refusal:
            response = controller._handle_exception_response(
                exc,
                operation='wrong_pin_test',
            )

        self.assertFalse(response['ok'])
        self.assertEqual(response['error']['code'], 'INVALID_ACTION_CODE')
        self.assertEqual(
            response['error']['reference'],
            'SEC-PIN-INVALID-TEST',
        )
        log_refusal.assert_called_once()

    def test_external_effect_boundary_can_disable_odoo_retry(self):
        controller = self._controller()

        response = controller._handle_exception_response(
            pg_errors.SerializationFailure('unsafe external effect'),
            operation='request_otp',
            allow_odoo_concurrency_retry=False,
        )

        self.assertFalse(response['ok'])
        self.assertEqual(response['error']['code'], 'SERVER_ERROR')
        self.assertTrue(response['error'].get('reference'))

    def test_signup_explicitly_disables_retry_around_sms_effect(self):
        source = inspect.getsource(AcpecMobileAuthApiPublic.signup)

        self.assertIn(
            'allow_odoo_concurrency_retry=False',
            source,
        )
