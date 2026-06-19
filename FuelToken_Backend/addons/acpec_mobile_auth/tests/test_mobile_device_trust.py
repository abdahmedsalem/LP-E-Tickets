# -*- coding: utf-8 -*-
from odoo.exceptions import AccessError, UserError
from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_mobile_auth.controllers.api_common import AcpecMobileAuthApiCommon


@tagged("post_install", "-at_install")
class TestMobileDeviceTrust(TransactionCase):

    def _group_ids(self):
        xmlids = (
            'base.group_portal',
            'acpec_mobile_auth.group_mobile_auth_user',
        )
        return [
            self.env.ref(xmlid).id
            for xmlid in xmlids
            if self.env.ref(xmlid, raise_if_not_found=False)
        ]

    def _create_mobile_user(self, login):
        user_model = self.env['res.users'].sudo().with_context(
            acpec_mobile_allow_password_write=True,
            no_reset_password=True,
        )
        return user_model.create({
            'name': login,
            'login': login,
            'email': login,
            'active': True,
            'mobile_only': True,
            'mobile_state': 'approved',
            'password': user_model._acpec_mobile_unusable_password(),
            'group_ids': [(6, 0, self._group_ids())],
        })

    def _create_session(self, login='device-trust-20a@example.com', device_uid='device-20a'):
        user = self._create_mobile_user(login)
        token_data = self.env['acpec.mobile.session'].sudo().create_for_user(user, {
            'device_uid': device_uid,
            'device_name': 'Android test',
            'platform': 'android',
        })
        return user, token_data

    def _controller_for_session(self, session):
        controller = AcpecMobileAuthApiCommon()
        controller._test_env = self.env
        controller._get_mobile_session = lambda required=True: session
        return controller

    def test_new_mobile_session_is_pending_trust_by_default(self):
        user, token_data = self._create_session()
        session = token_data['session']

        self.assertEqual(session.device_trust_state, 'pending_trust')
        self.assertFalse(session.device_trusted_at)

        controller = self._controller_for_session(session)
        with self.assertRaises(AccessError):
            controller._require_trusted_sensitive()

        # Normal mobile auth remains possible; only sensitive guard is stricter.
        self.assertTrue(
            self.env['acpec.mobile.session'].sudo().authenticate_access_token(token_data['access_token'])
        )

    def test_trusted_device_can_pass_sensitive_guard(self):
        user, token_data = self._create_session('trusted-device-20a@example.com')
        session = token_data['session']
        session.action_trust_device()

        controller = self._controller_for_session(session)
        allowed_user = controller._require_trusted_sensitive()

        self.assertEqual(allowed_user.id, user.id)
        self.assertEqual(session.device_trust_state, 'trusted')
        self.assertTrue(session.device_trusted_at)

    def test_sensitive_guard_rejects_session_without_device_uid(self):
        user, token_data = self._create_session('no-device-20a@example.com', device_uid=False)
        session = token_data['session']

        controller = self._controller_for_session(session)
        with self.assertRaises(AccessError):
            controller._require_trusted_sensitive()

        with self.assertRaises(UserError):
            session.action_trust_device()

    def test_sensitive_guard_rejects_blocked_device(self):
        user, token_data = self._create_session('blocked-device-20a@example.com')
        session = token_data['session']
        session.action_trust_device()
        session.action_block_device()

        controller = self._controller_for_session(session)
        with self.assertRaises(AccessError):
            controller._require_trusted_sensitive()

        self.assertEqual(session.device_trust_state, 'blocked')
        self.assertTrue(session.device_blocked_at)

    def test_refresh_keeps_device_trust_for_same_device_uid(self):
        user, token_data = self._create_session('refresh-same-device-20a@example.com', 'same-device-20a')
        session = token_data['session']
        session.action_trust_device()

        refreshed = self.env['acpec.mobile.session'].sudo().refresh_with_token(token_data['refresh_token'])
        new_session = refreshed['session']

        self.assertNotEqual(new_session, session)
        self.assertEqual(new_session.device_uid, 'same-device-20a')
        self.assertEqual(new_session.device_trust_state, 'trusted')
        self.assertTrue(new_session.device_trusted_at)

    def test_refresh_resets_device_trust_when_device_uid_changes(self):
        user, token_data = self._create_session('refresh-changed-device-20a@example.com', 'old-device-20a')
        session = token_data['session']
        session.action_trust_device()

        refreshed = self.env['acpec.mobile.session'].sudo().refresh_with_token(
            token_data['refresh_token'],
            {'device_uid': 'new-device-20a', 'platform': 'android'},
        )
        new_session = refreshed['session']

        self.assertNotEqual(new_session, session)
        self.assertEqual(new_session.device_uid, 'new-device-20a')
        self.assertEqual(new_session.device_trust_state, 'pending_trust')
        self.assertFalse(new_session.device_trusted_at)

    def test_profile_payload_exposes_device_trust_state(self):
        user, token_data = self._create_session('profile-device-20a@example.com', 'profile-device-20a')
        session = token_data['session']
        session.action_trust_device()

        controller = AcpecMobileAuthApiCommon()
        payload = controller._mobile_profile_payload(user, session=session)

        self.assertEqual(payload['device_uid'], 'profile-device-20a')
        self.assertEqual(payload['device_trust_state'], 'trusted')
        self.assertTrue(payload['device_trust_required_for_sensitive'])
        self.assertTrue(payload['device_trusted_at'])
