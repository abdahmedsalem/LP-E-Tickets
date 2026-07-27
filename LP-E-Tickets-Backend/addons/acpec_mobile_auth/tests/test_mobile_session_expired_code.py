# -*- coding: utf-8 -*-
from pathlib import Path

from odoo.exceptions import AccessError
from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_mobile_auth.controllers import api_common
from odoo.addons.acpec_mobile_auth.controllers.api_common import (
    AcpecMobileAuthApiCommon,
    MobileSessionExpiredError,
)


@tagged('post_install', '-at_install')
class TestMobileSessionExpiredCode(TransactionCase):

    def test_session_expired_error_returns_stable_public_code(self):
        controller = AcpecMobileAuthApiCommon()
        response = controller._handle_exception_response(
            MobileSessionExpiredError(),
            operation='wallet_current',
            endpoint='/api/acpec/fueltoken/v1/mobile/wallet/current',
        )

        self.assertFalse(response['ok'])
        self.assertFalse(response['success'])
        self.assertEqual(response['error']['code'], 'SESSION_EXPIRED')
        self.assertEqual(
            response['error']['message'],
            'Session mobile invalide ou expirée.',
        )

    def test_generic_access_error_keeps_generic_access_error_code(self):
        controller = AcpecMobileAuthApiCommon()
        response = controller._handle_exception_response(
            AccessError('Droits insuffisants pour cette opération.'),
            operation='generic_access_error',
            endpoint='/api/acpec/fueltoken/v1/mobile/test',
        )

        self.assertFalse(response['ok'])
        self.assertEqual(response['error']['code'], 'ACCESS_ERROR')

    def test_source_contract_uses_session_expired_for_mobile_session_refusal(self):
        source = Path(api_common.__file__).read_text(encoding='utf-8')

        self.assertIn('class MobileSessionExpiredError', source)
        self.assertIn('class MobileSessionClosedError', source)
        self.assertIn(
            'isinstance(exc, (MobileSessionExpiredError, MobileSessionClosedError))',
            source,
        )
        self.assertIn("raise MobileSessionExpiredError()", source)
        self.assertIn("exc.acpec_public_code", source)
        self.assertIn("action=getattr(exc, 'acpec_public_action', False)", source)
        self.assertIn("'SESSION_EXPIRED'", source)
