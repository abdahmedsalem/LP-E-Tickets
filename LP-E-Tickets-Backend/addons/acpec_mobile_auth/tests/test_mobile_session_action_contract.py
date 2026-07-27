# -*- coding: utf-8 -*-
from pathlib import Path

from odoo.exceptions import AccessError
from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_mobile_auth.controllers import api_session
from odoo.addons.acpec_mobile_auth.controllers.api_common import (
    AcpecMobileAuthApiCommon,
    MobileSessionClosedError,
    MobileSessionExpiredError,
)


@tagged('post_install', '-at_install')
class TestMobileSessionActionContract(TransactionCase):

    def test_session_expired_returns_refresh_required_action(self):
        controller = AcpecMobileAuthApiCommon()
        response = controller._handle_exception_response(
            MobileSessionExpiredError(),
            operation='wallet_current',
            endpoint='/api/acpec/fueltoken/v1/mobile/wallet/current',
        )

        self.assertFalse(response['ok'])
        self.assertFalse(response['success'])
        self.assertEqual(response['error']['code'], 'SESSION_EXPIRED')
        self.assertEqual(response['error']['action'], 'REFRESH_REQUIRED')

    def test_session_closed_returns_logout_required_action(self):
        controller = AcpecMobileAuthApiCommon()
        response = controller._handle_exception_response(
            MobileSessionClosedError(),
            operation='refresh',
            endpoint='/api/acpec/mobile_auth/v1/refresh',
        )

        self.assertFalse(response['ok'])
        self.assertFalse(response['success'])
        self.assertEqual(response['error']['code'], 'SESSION_CLOSED')
        self.assertEqual(response['error']['action'], 'LOGOUT_REQUIRED')
        self.assertEqual(
            response['error']['message'],
            'Session terminée. Veuillez vous reconnecter.',
        )

    def test_generic_access_error_does_not_receive_logout_action(self):
        controller = AcpecMobileAuthApiCommon()
        response = controller._handle_exception_response(
            AccessError('Droits insuffisants pour cette opération.'),
            operation='generic_access_error',
            endpoint='/api/acpec/fueltoken/v1/mobile/test',
        )

        self.assertFalse(response['ok'])
        self.assertEqual(response['error']['code'], 'ACCESS_ERROR')
        self.assertNotIn('action', response['error'])

    def test_refresh_controller_maps_terminal_refresh_failure_to_session_closed(self):
        source = Path(api_session.__file__).read_text(encoding='utf-8')

        self.assertIn('MobileSessionClosedError', source)
        self.assertIn('except AccessError as exc:', source)
        self.assertIn(
            "raise MobileSessionClosedError(debug_reason='refresh_session_closed') from exc",
            source,
        )
        self.assertIn("'REFRESH_TOKEN_REQUIRED'", source)
        self.assertIn("action='LOGOUT_REQUIRED'", source)
