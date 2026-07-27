# -*- coding: utf-8 -*-
import inspect
from odoo.exceptions import AccessError
from odoo.tests.common import TransactionCase

from odoo.addons.acpec_mobile_auth.controllers.api_session import AcpecMobileAuthApiSession


class TestMobileLogoutNoDeviceTrustWrite(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()

        cls.mobile_user = cls.env['res.users'].with_context(no_reset_password=True).sudo().create({
            'name': 'J5C Logout Mobile User',
            'login': 'j5c_logout_mobile_user',
            'email': 'j5c_logout_mobile_user@example.com',
            'mobile_phone': '49990001',
            'acpec_mobile_only': True,
            'acpec_mobile_state': 'approved',
            'company_id': cls.env.company.id,
            'company_ids': [(6, 0, [cls.env.company.id])],
            'group_ids': [(6, 0, [
                cls.env.ref('base.group_portal').id,
                cls.env.ref('acpec_mobile_auth.group_mobile_auth_user').id,
            ])],
        })

        token_data = cls.env['acpec.mobile.session'].sudo().create_for_user(cls.mobile_user, {
            'device_uid': 'ft-android-j5c-logout-no-trust-write',
            'device_name': 'J5C Logout Test Device',
            'platform': 'android',
            'app_version': 'test',
        })
        cls.session = token_data['session']
        cls.session.sudo().action_trust_device()

    def test_mobile_logout_can_revoke_session_without_device_trust_admin(self):
        self.session.invalidate_recordset([
            'state',
            'revoked_at',
            'device_trust_state',
            'device_trusted_at',
            'device_id',
        ])
        device = self.session.device_id
        device.invalidate_recordset(['trust_state', 'trusted_at'])

        self.assertEqual(self.session.state, 'active')
        self.assertEqual(self.session.device_trust_state, 'trusted')
        self.assertEqual(device.trust_state, 'trusted')

        with self.assertRaises(AccessError):
            self.session.with_user(self.mobile_user).action_revoke()

        self.session.invalidate_recordset(['state', 'revoked_at', 'device_trust_state'])
        device.invalidate_recordset(['trust_state'])
        self.assertEqual(self.session.state, 'active')
        self.assertEqual(self.session.device_trust_state, 'trusted')
        self.assertEqual(device.trust_state, 'trusted')

        self.session.with_user(self.mobile_user)._revoke_for_mobile_logout()
        self.session.invalidate_recordset(['state', 'revoked_at', 'device_trust_state'])
        device.invalidate_recordset(['trust_state'])

        self.assertEqual(self.session.state, 'revoked')
        self.assertTrue(self.session.revoked_at)
        self.assertEqual(self.session.device_trust_state, 'trusted')
        self.assertEqual(device.trust_state, 'trusted')

        # Idempotent: second logout should not fail or change device trust.
        self.session.with_user(self.mobile_user)._revoke_for_mobile_logout()
        self.session.invalidate_recordset(['state', 'device_trust_state'])
        device.invalidate_recordset(['trust_state'])

        self.assertEqual(self.session.state, 'revoked')
        self.assertEqual(self.session.device_trust_state, 'trusted')
        self.assertEqual(device.trust_state, 'trusted')

    def test_session_check_contract_does_not_use_device_trust_admin_actions(self):
        source = inspect.getsource(AcpecMobileAuthApiSession.session_check)

        self.assertIn("_get_mobile_session(required=False)", source)
        self.assertIn("_session_payload(session)", source)

        forbidden_fragments = [
            "action_revoke",
            "_revoke_for_mobile_logout",
            "action_trust_device",
            "action_reset_device_trust",
            "action_block",
            "_check_device_trust_admin",
            ".write(",
            "device_trust_state =",
            "trust_state =",
        ]
        for fragment in forbidden_fragments:
            self.assertNotIn(fragment, source)

