# -*- coding: utf-8 -*-
from odoo.exceptions import UserError
from odoo.tests.common import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestMobileDeviceTrustHardening(TransactionCase):

    def setUp(self):
        super().setUp()
        group = self.env.ref('acpec_mobile_auth.group_mobile_auth_admin', raise_if_not_found=False)
        if group:
            self.env.user.sudo().write({'group_ids': [(4, group.id)]})

    def _create_mobile_user(self, phone):
        portal_group = self.env.ref('base.group_portal')
        mobile_group = self.env.ref('acpec_mobile_auth.group_mobile_auth_user')
        return self.env['res.users'].with_context(no_reset_password=True).create({
            'name': 'F2N Mobile User %s' % phone,
            'login': phone,
            'mobile_phone': phone,
            'mobile_only': True,
            'mobile_state': 'self_registered',
            'group_ids': [(6, 0, [portal_group.id, mobile_group.id])],
        })

    def _create_session(self, user, device_uid):
        result = self.env['acpec.mobile.session'].create_for_user(user, {
            'device_uid': device_uid,
            'device_name': device_uid,
            'platform': 'android',
            'app_version': '1.0.0',
        })
        if isinstance(result, dict):
            return result['session']
        return result

    def _assert_device_chatter_contains(self, device, text):
        messages = self.env['mail.message'].sudo().search([
            ('model', '=', 'acpec.mobile.device'),
            ('res_id', '=', device.id),
            ('body', 'ilike', text),
        ], limit=1)
        self.assertTrue(messages, "Chatter device must contain: %s" % text)

    def test_f2n_block_device_wizard_requires_reason_and_revokes_sessions(self):
        user = self._create_mobile_user('43002001')
        session = self._create_session(user, 'ft-f2n-block-wizard')
        device = session.device_id
        device.action_trust_device()

        wizard = self.env['acpec.mobile.device.trust.wizard'].create({
            'device_id': device.id,
            'operation': 'block',
            'reason': '   ',
        })
        with self.assertRaises(UserError):
            wizard.action_confirm()

        reason = 'Téléphone déclaré perdu'
        wizard.reason = reason
        wizard.action_confirm()

        device.invalidate_recordset(['trust_state', 'blocked_reason', 'blocked_at'])
        session.invalidate_recordset(['state', 'revoked_at', 'device_trust_state'])

        self.assertEqual(device.trust_state, 'blocked')
        self.assertEqual(device.blocked_reason, reason)
        self.assertTrue(device.blocked_at)
        self.assertEqual(session.state, 'revoked')
        self.assertTrue(session.revoked_at)
        self.assertEqual(session.device_trust_state, 'blocked')
        self._assert_device_chatter_contains(device, reason)

    def test_f2n_blocked_device_cannot_be_trusted_directly(self):
        user = self._create_mobile_user('43002002')
        session = self._create_session(user, 'ft-f2n-blocked-no-direct-trust')
        device = session.device_id

        device.action_block_device(reason='Compromission suspectée')
        device.invalidate_recordset(['trust_state'])
        self.assertEqual(device.trust_state, 'blocked')

        with self.assertRaises(UserError):
            device.action_trust_device()

    def test_f2n_blocked_device_reset_requires_reason_then_returns_pending(self):
        user = self._create_mobile_user('43002003')
        session = self._create_session(user, 'ft-f2n-blocked-reset')
        device = session.device_id

        device.action_block_device(reason='Ancien blocage à réviser')
        with self.assertRaises(UserError):
            device.action_reset_device_trust()

        reason = 'Contrôle BO effectué'
        device.action_reset_device_trust(reason=reason)
        device.invalidate_recordset(['trust_state', 'blocked_at', 'blocked_by', 'blocked_reason'])

        self.assertEqual(device.trust_state, 'pending_trust')
        self.assertFalse(device.blocked_at)
        self.assertFalse(device.blocked_by)
        self.assertFalse(device.blocked_reason)
        self._assert_device_chatter_contains(device, reason)

    def test_f2n_user_blocked_device_cannot_be_trusted(self):
        user = self._create_mobile_user('43002004')
        session = self._create_session(user, 'ft-f2n-user-blocked-device')
        device = session.device_id

        user.sudo().write({'mobile_state': 'blocked'})

        with self.assertRaises(UserError):
            device.action_trust_device()

    def test_f2n_device_views_use_wizards_for_sensitive_block_reset(self):
        device_view = self.env.ref('acpec_mobile_auth.view_acpec_mobile_device_form')
        session_view = self.env.ref('acpec_mobile_auth.view_acpec_mobile_session_form')

        self.assertIn('action_trust_device', device_view.arch_db)
        self.assertIn('action_open_block_device_wizard', device_view.arch_db)
        self.assertIn('action_open_reset_device_trust_wizard', device_view.arch_db)
        self.assertIn("trust_state != 'pending_trust'", device_view.arch_db)

        self.assertIn('action_trust_device', session_view.arch_db)
        self.assertIn('action_open_block_device_wizard', session_view.arch_db)
        self.assertIn('action_open_reset_device_trust_wizard', session_view.arch_db)
        self.assertIn("device_trust_state != 'pending_trust'", session_view.arch_db)
