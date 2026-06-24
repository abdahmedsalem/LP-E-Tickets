# -*- coding: utf-8 -*-
from odoo.exceptions import AccessError
from odoo.tests.common import TransactionCase, tagged


@tagged("post_install", "-at_install")
class TestMobileStateGate(TransactionCase):

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

    def _create_mobile_user(self, login, state='approved', active=True):
        user_model = self.env['res.users'].sudo().with_context(
            acpec_mobile_allow_password_write=True,
            no_reset_password=True,
        )
        return user_model.create({
            'name': login,
            'login': login,
            'email': login,
            'active': active,
            'mobile_only': True,
            'mobile_state': state,
            'password': user_model._acpec_mobile_unusable_password(),
            'group_ids': [(6, 0, self._group_ids())],
        })

    def test_approved_mobile_user_can_create_session(self):
        user = self._create_mobile_user('approved-mobile-19a@example.com', 'approved')
        token_data = self.env['acpec.mobile.session'].sudo().create_for_user(user)
        self.assertTrue(token_data['access_token'])
        self.assertEqual(token_data['session'].state, 'active')

    def test_pending_mobile_user_cannot_create_session(self):
        user = self._create_mobile_user('pending-mobile-19a@example.com', 'pending')
        with self.assertRaises(AccessError):
            self.env['acpec.mobile.session'].sudo().create_for_user(user)

    def test_rejected_mobile_user_cannot_create_session(self):
        user = self._create_mobile_user('rejected-mobile-19a@example.com', 'rejected')
        with self.assertRaises(AccessError):
            self.env['acpec.mobile.session'].sudo().create_for_user(user)

    def test_blocked_mobile_user_cannot_create_session(self):
        user = self._create_mobile_user('blocked-mobile-19a@example.com', 'blocked')
        with self.assertRaises(AccessError):
            self.env['acpec.mobile.session'].sudo().create_for_user(user)

    def test_mobile_sessions_are_revoked_when_user_is_blocked(self):
        user = self._create_mobile_user('block-revoke-mobile-19a@example.com', 'approved')
        token_data = self.env['acpec.mobile.session'].sudo().create_for_user(user)
        session = token_data['session']

        user.sudo().write({'mobile_state': 'blocked'})
        session.invalidate_recordset(['state', 'revoked_at'])

        self.assertEqual(session.state, 'revoked')
        self.assertTrue(session.revoked_at)

    def test_refresh_revokes_session_if_user_is_no_longer_approved(self):
        user = self._create_mobile_user('refresh-pending-mobile-19a@example.com', 'approved')
        token_data = self.env['acpec.mobile.session'].sudo().create_for_user(user)
        session = token_data['session']

        user.sudo().write({'mobile_state': 'pending'})
        session.invalidate_recordset(['state'])

        self.assertEqual(session.state, 'revoked')

        with self.assertRaises(AccessError):
            self.env['acpec.mobile.session'].sudo().refresh_with_token(token_data['refresh_token'])

    def test_deactivating_mobile_user_revokes_sessions(self):
        user = self._create_mobile_user('inactive-mobile-19a@example.com', 'approved')
        token_data = self.env['acpec.mobile.session'].sudo().create_for_user(user)
        session = token_data['session']

        user.sudo().write({'active': False})
        session.invalidate_recordset(['state', 'revoked_at'])

        self.assertEqual(session.state, 'revoked')
        self.assertTrue(session.revoked_at)

    def test_self_registered_mobile_user_can_create_session_for_device_enrollment(self):
        user = self._create_mobile_user(
            'self-registered-mobile-39a@example.com',
            'self_registered',
        )

        token_data = self.env['acpec.mobile.session'].sudo().create_for_user(user, {
            'device_uid': 'self-registered-device-39a',
            'platform': 'android',
        })
        session = token_data['session']

        self.assertEqual(session.state, 'active')
        self.assertEqual(session.device_trust_state, 'pending_trust')
        session.invalidate_recordset(['is_device_approval_candidate'])
        self.assertTrue(session.is_device_approval_candidate)

    def test_self_registered_state_does_not_revoke_active_session(self):
        user = self._create_mobile_user(
            'self-registered-no-revoke-39a@example.com',
            'self_registered',
        )
        token_data = self.env['acpec.mobile.session'].sudo().create_for_user(user, {
            'device_uid': 'self-registered-no-revoke-device-39a',
            'platform': 'android',
        })
        session = token_data['session']

        user.sudo().write({'mobile_state': 'self_registered'})
        session.invalidate_recordset(['state', 'revoked_at'])

        self.assertEqual(session.state, 'active')
        self.assertFalse(session.revoked_at)
