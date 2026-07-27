# -*- coding: utf-8 -*-

from odoo.tests.common import TransactionCase
from odoo.exceptions import AccessError

from odoo.addons.acpec_mobile_auth.controllers.api_common import AcpecMobileAuthApiCommon


class TestMobileUserBlockedPublicCode(TransactionCase):

    def setUp(self):
        super().setUp()
        self.controller = AcpecMobileAuthApiCommon()

    def test_h7_mobile_user_blocked_public_code_is_registered(self):
        self.assertEqual(
            self.controller.SENSITIVE_PUBLIC_ERROR_FAMILIES.get('MOBILE_USER_BLOCKED'),
            'Ce compte mobile est bloqu\u00e9. Contactez l\u2019administrateur.',
        )
        self.assertIn('mobile_user_blocked', self.controller.SENSITIVE_DEBUG_REASONS)

    def test_h7_detects_mobile_user_blocked_access_error(self):
        self.assertTrue(
            self.controller._is_mobile_user_blocked_access_error(
                AccessError('Compte mobile bloqu\u00e9.')
            )
        )
        self.assertTrue(
            self.controller._is_mobile_user_blocked_access_error(
                AccessError('Mobile account blocked.')
            )
        )
        self.assertFalse(
            self.controller._is_mobile_user_blocked_access_error(
                AccessError('Acc\u00e8s refus\u00e9 : soci\u00e9t\u00e9 non autoris\u00e9e.')
            )
        )
        self.assertFalse(
            self.controller._is_mobile_user_blocked_access_error(
                AccessError('Appareil mobile bloqu\u00e9.')
            )
        )

    def test_h7_exposes_code_for_session_api_but_not_public_otp(self):
        self.controller._test_request_path = '/api/acpec/mobile_auth/v1/refresh'
        self.assertTrue(
            self.controller._should_expose_mobile_user_blocked_code(
                operation='session_refresh'
            )
        )

        self.controller._test_request_path = '/api/acpec/mobile_auth/v1/request-otp'
        self.assertFalse(
            self.controller._should_expose_mobile_user_blocked_code(
                operation='request_otp'
            )
        )

        self.controller._test_request_path = '/api/acpec/mobile_auth/v1/verify-otp'
        self.assertFalse(
            self.controller._should_expose_mobile_user_blocked_code(
                operation='verify_otp'
            )
        )

    def test_h7_access_error_handler_contains_mobile_user_blocked_contract(self):
        source = AcpecMobileAuthApiCommon._handle_exception_response.__code__.co_names
        self.assertIn('_is_mobile_user_blocked_access_error', source)
        self.assertIn('_should_expose_mobile_user_blocked_code', source)
        self.assertIn('_sensitive_refusal_response', source)
