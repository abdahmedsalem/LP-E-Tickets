# -*- coding: utf-8 -*-
from odoo import fields
from odoo.exceptions import AccessError
from odoo.tools.safe_eval import safe_eval
from odoo.tests.common import TransactionCase, tagged


@tagged("post_install", "-at_install")
class TestMobileDeviceTrustBackoffice(TransactionCase):

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

    def _create_admin_user(self, login='mobile-auth-admin-20c@example.com'):
        Users = self.env['res.users'].sudo().with_context(no_reset_password=True)
        group_user = self.env.ref('base.group_user')
        group_admin = self.env.ref('acpec_mobile_auth.group_mobile_auth_admin')
        return Users.create({
            'name': 'Mobile Auth Admin 20C',
            'login': login,
            'email': login,
            'password': 'Admin20C!ChangeMe',
            'group_ids': [(6, 0, [group_user.id, group_admin.id])],
        })

    def _create_regular_internal_user(self, login='regular-internal-20c@example.com'):
        Users = self.env['res.users'].sudo().with_context(no_reset_password=True)
        group_user = self.env.ref('base.group_user')
        return Users.create({
            'name': 'Regular Internal 20C',
            'login': login,
            'email': login,
            'password': 'Regular20C!ChangeMe',
            'group_ids': [(6, 0, [group_user.id])],
        })

    def _create_session(self):
        user = self._create_mobile_user('device-trust-backoffice-20c@example.com')
        token_data = self.env['acpec.mobile.session'].sudo().create_for_user(user, {
            'device_uid': 'device-backoffice-20c',
            'device_name': 'Android 20C',
            'platform': 'android',
        })
        return token_data['session']

    def test_mobile_auth_admin_can_trust_block_and_reset_device(self):
        session = self._create_session()
        admin = self._create_admin_user()

        session.with_user(admin).action_trust_device()
        session.invalidate_recordset(['device_trust_state', 'device_trusted_at', 'device_blocked_at'])

        self.assertEqual(session.device_trust_state, 'trusted')
        self.assertTrue(session.device_trusted_at)
        self.assertFalse(session.device_blocked_at)
        self.assertTrue(session.message_ids.filtered(lambda msg: 'Device mobile approuvé' in (msg.body or '')))

        session.with_user(admin).action_block_device()
        session.invalidate_recordset(['device_trust_state', 'device_blocked_at'])

        self.assertEqual(session.device_trust_state, 'blocked')
        self.assertTrue(session.device_blocked_at)
        self.assertTrue(session.message_ids.filtered(lambda msg: 'bloqué par' in (msg.body or '')))

        session.with_user(admin).action_reset_device_trust()
        session.invalidate_recordset(['device_trust_state', 'device_trusted_at', 'device_blocked_at'])

        self.assertEqual(session.device_trust_state, 'pending_trust')
        self.assertFalse(session.device_trusted_at)
        self.assertFalse(session.device_blocked_at)
        self.assertTrue(session.message_ids.filtered(lambda msg: 'Confiance device remise en attente' in (msg.body or '')))

    def test_regular_internal_user_cannot_change_device_trust(self):
        session = self._create_session()
        regular_user = self._create_regular_internal_user()

        with self.assertRaises(AccessError):
            session.with_user(regular_user).action_trust_device()

        with self.assertRaises(AccessError):
            session.with_user(regular_user).action_block_device()

        with self.assertRaises(AccessError):
            session.with_user(regular_user).action_reset_device_trust()

    def test_session_views_expose_device_trust_backoffice_controls(self):
        list_arch = self.env.ref('acpec_mobile_auth.view_acpec_mobile_session_tree').arch_db
        form_arch = self.env.ref('acpec_mobile_auth.view_acpec_mobile_session_form').arch_db

        self.assertIn('device_uid', list_arch)
        self.assertIn('device_trust_state', list_arch)

        self.assertIn('action_trust_device', form_arch)
        self.assertIn('action_block_device', form_arch)
        self.assertIn('action_reset_device_trust', form_arch)
        self.assertIn('device_trust_state', form_arch)
        self.assertIn('device_trusted_at', form_arch)
        self.assertIn('device_blocked_at', form_arch)
        self.assertIn('device_trust_note', form_arch)
        self.assertIn('acpec_mobile_auth.group_mobile_auth_admin', form_arch)

    def test_mobile_identity_fields_are_available_for_device_worklist(self):
        user = self._create_mobile_user('device-label-32b@example.com')
        user.write({
            'name': 'Test Mobile 32B',
            'mobile_phone': '32342008',
        })

        token_data = self.env['acpec.mobile.session'].sudo().create_for_user(user, {
            'device_uid': 'device-label-32b',
            'device_name': 'Android 32B',
            'platform': 'android',
        })
        session = token_data['session']
        session.invalidate_recordset(['mobile_phone', 'mobile_user_label'])

        self.assertEqual(session.mobile_phone, '32342008')
        self.assertEqual(session.mobile_user_label, 'Test Mobile 32B - 32342008')

    def test_device_approval_candidate_keeps_latest_active_pending_session_only(self):
        user = self._create_mobile_user('device-candidate-32b@example.com')
        Session = self.env['acpec.mobile.session'].sudo()

        first = Session.create_for_user(user, {
            'device_uid': 'same-device-32b',
            'device_name': 'Android 32B',
            'platform': 'android',
        })['session']
        latest = Session.create_for_user(user, {
            'device_uid': 'same-device-32b',
            'device_name': 'Android 32B',
            'platform': 'android',
        })['session']

        first.invalidate_recordset(['is_device_approval_candidate'])
        latest.invalidate_recordset(['is_device_approval_candidate'])

        self.assertFalse(first.is_device_approval_candidate)
        self.assertTrue(latest.is_device_approval_candidate)

    def test_device_approval_candidate_is_cleared_when_latest_active_is_trusted(self):
        user = self._create_mobile_user('device-candidate-trusted-32b@example.com')
        Session = self.env['acpec.mobile.session'].sudo()

        old_pending = Session.create_for_user(user, {
            'device_uid': 'trusted-latest-device-32b',
            'device_name': 'Android 32B',
            'platform': 'android',
        })['session']
        latest = Session.create_for_user(user, {
            'device_uid': 'trusted-latest-device-32b',
            'device_name': 'Android 32B',
            'platform': 'android',
        })['session']

        latest.write({
            'device_trust_state': 'trusted',
            'device_trusted_at': fields.Datetime.now(),
        })

        old_pending.invalidate_recordset(['is_device_approval_candidate'])
        latest.invalidate_recordset(['is_device_approval_candidate'])

        self.assertFalse(old_pending.is_device_approval_candidate)
        self.assertFalse(latest.is_device_approval_candidate)

    def test_devices_to_approve_action_uses_defensive_candidate_domain(self):
        action = self.env.ref(
            'acpec_fueltoken_backoffice_ui.action_backoffice_mobile_devices_to_approve',
            raise_if_not_found=False,
        )
        if not action:
            return

        domain = safe_eval(action.domain)
        context = safe_eval(action.context)

        self.assertIn(('is_device_approval_candidate', '=', True), domain)
        self.assertIn(('device_trust_state', '=', 'pending_trust'), domain)
        self.assertIn(('state', '=', 'active'), domain)
        self.assertIn(('device_uid', '!=', False), domain)
        self.assertIn(('device_uid', '!=', ''), domain)
        self.assertIn(('user_id.mobile_only', '=', True), domain)
        self.assertIn(('user_id.mobile_state', '=', 'approved'), domain)

        self.assertEqual(context.get('search_default_approval_candidate'), 1)
        self.assertEqual(context.get('search_default_group_by_mobile_user_label'), 1)
        self.assertEqual(
            action.search_view_id,
            self.env.ref('acpec_mobile_auth.view_acpec_mobile_session_search'),
        )
