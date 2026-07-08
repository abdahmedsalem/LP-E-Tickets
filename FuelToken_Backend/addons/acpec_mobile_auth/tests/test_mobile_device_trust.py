# -*- coding: utf-8 -*-
from odoo.exceptions import AccessError, ValidationError
from odoo.tests.common import TransactionCase, tagged


def _acpec_test_mobile_phone(label):
    """Return a deterministic canonical 8-digit mobile phone for test labels."""
    value = 2166136261
    for char in str(label):
        value ^= ord(char)
        value = (value * 16777619) % 10000000
    return "3%07d" % value

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
            'login': _acpec_test_mobile_phone(login),
            'mobile_phone': _acpec_test_mobile_phone(login),
            'email': login,
            'active': True,
            'acpec_mobile_only': True,
            'acpec_mobile_state': 'approved',
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

    def test_create_for_user_requires_stable_device_uid(self):
        user = self._create_mobile_user('no-device-43a@example.com')
        Session = self.env['acpec.mobile.session'].sudo()

        for device_uid in (False, '', 'flutter-android-local'):
            with self.assertRaises(ValidationError):
                Session.create_for_user(user, {
                    'device_uid': device_uid,
                    'device_name': 'Android test',
                    'platform': 'android',
                })

        self.assertFalse(Session.search([
            ('user_id', '=', user.id),
            ('state', '=', 'active'),
        ], limit=1))

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

    def test_blocked_device_access_and_refresh_tokens_are_unusable(self):
        user, token_data = self._create_session('blocked-runtime-43a@example.com')
        session = token_data['session']
        session.action_trust_device()
        session.action_block_device()
        session.invalidate_recordset(['state', 'revoked_at', 'device_trust_state'])

        self.assertEqual(session.device_trust_state, 'blocked')
        self.assertEqual(session.state, 'revoked')
        self.assertFalse(
            self.env['acpec.mobile.session'].sudo().authenticate_access_token(token_data['access_token'])
        )

        with self.assertRaises(AccessError):
            self.env['acpec.mobile.session'].sudo().refresh_with_token(token_data['refresh_token'])

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

    def test_relogin_same_stable_device_inherits_trusted_after_logout(self):
        user = self._create_mobile_user('trusted-relogin-41a@example.com')
        Session = self.env['acpec.mobile.session'].sudo()
        device_uid = 'ft-test-relogin-41a'

        first = Session.create_for_user(user, {
            'device_uid': device_uid,
            'device_name': 'Android 41A',
            'platform': 'android',
        })
        first_session = first['session']
        self.assertEqual(first_session.device_trust_state, 'pending_trust')

        first_session.action_trust_device()
        first_session.action_revoke()

        second = Session.create_for_user(user, {
            'device_uid': device_uid,
            'device_name': 'Android 41A',
            'platform': 'android',
        })
        second_session = second['session']

        self.assertNotEqual(second_session, first_session)
        self.assertEqual(second_session.device_uid, device_uid)
        self.assertEqual(second_session.device_trust_state, 'trusted')
        self.assertTrue(second_session.device_trusted_at)
        self.assertFalse(second_session.is_device_approval_candidate)

    def test_relogin_same_stable_blocked_device_is_refused(self):
        user = self._create_mobile_user('blocked-relogin-43a@example.com')
        Session = self.env['acpec.mobile.session'].sudo()
        device_uid = 'ft-test-blocked-43a'

        first = Session.create_for_user(user, {
            'device_uid': device_uid,
            'platform': 'android',
        })
        first_session = first['session']
        first_session.action_block_device()
        first_session.invalidate_recordset(['state', 'revoked_at', 'device_trust_state'])

        self.assertEqual(first_session.device_trust_state, 'blocked')
        self.assertEqual(first_session.state, 'revoked')
        self.assertTrue(first_session.revoked_at)

        with self.assertRaises(AccessError):
            Session.create_for_user(user, {
                'device_uid': device_uid,
                'platform': 'android',
            })

        new_active = Session.search([
            ('user_id', '=', user.id),
            ('device_uid', '=', device_uid),
            ('id', '!=', first_session.id),
            ('state', '=', 'active'),
        ], limit=1)
        self.assertFalse(new_active)

    def test_reset_device_trust_prevents_future_relogin_inheritance(self):
        user = self._create_mobile_user('reset-relogin-41a@example.com')
        Session = self.env['acpec.mobile.session'].sudo()
        device_uid = 'ft-test-reset-41a'

        first = Session.create_for_user(user, {
            'device_uid': device_uid,
            'platform': 'android',
        })
        first_session = first['session']
        first_session.action_trust_device()
        first_session.action_reset_device_trust()
        first_session.action_revoke()

        second = Session.create_for_user(user, {
            'device_uid': device_uid,
            'platform': 'android',
        })
        second_session = second['session']

        self.assertEqual(second_session.device_trust_state, 'pending_trust')
        self.assertFalse(second_session.device_trusted_at)
        self.assertTrue(second_session.is_device_approval_candidate)

    def test_rejected_user_does_not_inherit_trusted_device_on_relogin(self):
        user = self._create_mobile_user('rejected-relogin-41a@example.com')
        Session = self.env['acpec.mobile.session'].sudo()
        device_uid = 'ft-test-rejected-relogin-41a'

        first = Session.create_for_user(user, {
            'device_uid': device_uid,
            'platform': 'android',
        })
        first_session = first['session']
        first_session.action_trust_device()

        user.sudo().write({'acpec_mobile_state': 'rejected'})

        with self.assertRaises(AccessError):
            Session.create_for_user(user, {
                'device_uid': device_uid,
                'platform': 'android',
            })

        new_active = Session.search([
            ('user_id', '=', user.id),
            ('device_uid', '=', device_uid),
            ('id', '!=', first_session.id),
            ('state', '=', 'active'),
        ], limit=1)
        self.assertFalse(new_active)

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
