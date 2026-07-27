# -*- coding: utf-8 -*-
from odoo import fields
from odoo.exceptions import AccessError, UserError, ValidationError
from odoo.tools.safe_eval import safe_eval
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

    def _create_mobile_user(self, label, phone=None, name=None):
        user_model = self.env['res.users'].sudo().with_context(
            acpec_mobile_allow_password_write=True,
            no_reset_password=True,
        )
        mobile_phone = phone or _acpec_test_mobile_phone(label)
        return user_model.create({
            'name': name or label,
            'login': mobile_phone,
            'mobile_phone': mobile_phone,
            'active': True,
            'acpec_mobile_only': True,
            'acpec_mobile_state': 'approved',
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

    def _controller_for_session(self, session):
        controller = AcpecMobileAuthApiCommon()
        controller._test_env = self.env
        controller._get_mobile_session = lambda required=True: session
        return controller

    def test_mobile_auth_admin_can_trust_block_and_reset_device(self):
        session = self._create_session()
        device = session.device_id
        self.assertTrue(device)
        admin = self._create_admin_user()

        session.with_user(admin).action_trust_device()
        session.invalidate_recordset(['device_trust_state', 'device_trusted_at', 'device_blocked_at'])
        device.invalidate_recordset(['trust_state', 'message_ids'])

        self.assertEqual(session.device_trust_state, 'trusted')
        self.assertTrue(session.device_trusted_at)
        self.assertFalse(session.device_blocked_at)
        self.assertEqual(device.trust_state, 'trusted')
        self.assertTrue(device.message_ids.filtered(
            lambda msg: 'Device mobile approuvé' in (msg.body or '')
            and (session.name or '') in (msg.body or '')
        ))

        self.env['acpec.mobile.device.trust.wizard'].with_user(admin).create({
            'session_id': session.id,
            'operation': 'block',
            'reason': 'F2N blocage device depuis test BO',
        }).action_confirm()
        session.invalidate_recordset(['state', 'revoked_at', 'device_trust_state', 'device_blocked_at'])
        device.invalidate_recordset(['trust_state', 'message_ids'])

        self.assertEqual(session.device_trust_state, 'blocked')
        self.assertTrue(session.device_blocked_at)
        self.assertEqual(session.state, 'revoked')
        self.assertTrue(session.revoked_at)
        self.assertEqual(device.trust_state, 'blocked')
        self.assertTrue(device.message_ids.filtered(
            lambda msg: 'bloqué par' in (msg.body or '')
            and (session.name or '') in (msg.body or '')
        ))

        self.env['acpec.mobile.device.trust.wizard'].with_user(admin).create({
            'session_id': session.id,
            'operation': 'reset',
            'reason': 'F2N remise en attente device depuis test BO',
        }).action_confirm()
        session.invalidate_recordset(['device_trust_state', 'device_trusted_at', 'device_blocked_at'])
        device.invalidate_recordset(['trust_state', 'message_ids'])

        self.assertEqual(session.device_trust_state, 'pending_trust')
        self.assertFalse(session.device_trusted_at)
        self.assertFalse(session.device_blocked_at)
        self.assertEqual(device.trust_state, 'pending_trust')
        self.assertTrue(device.message_ids.filtered(
            lambda msg: 'Confiance device remise en attente' in (msg.body or '')
            and (session.name or '') in (msg.body or '')
        ))


    def test_trusting_new_device_resets_previous_trusted_device_for_same_user(self):
        user = self._create_mobile_user('single-trusted-device-43c@example.com')
        Session = self.env['acpec.mobile.session'].sudo()

        first = Session.create_for_user(user, {
            'device_uid': 'ft-single-trusted-device-a-43c',
            'device_name': 'Android A 43C',
            'platform': 'android',
        })['session']
        first.action_trust_device()
        first.invalidate_recordset(['device_trust_state', 'device_trusted_at'])

        self.assertEqual(first.device_trust_state, 'trusted')
        self.assertTrue(first.device_trusted_at)

        second = Session.create_for_user(user, {
            'device_uid': 'ft-single-trusted-device-b-43c',
            'device_name': 'Android B 43C',
            'platform': 'android',
        })['session']
        second.invalidate_recordset(['device_trust_state', 'device_trusted_at'])
        first.invalidate_recordset(['device_trust_state'])

        self.assertEqual(second.device_trust_state, 'pending_trust')
        self.assertFalse(second.device_trusted_at)
        self.assertEqual(first.device_trust_state, 'trusted')

        second.action_trust_device()
        first.invalidate_recordset([
            'state',
            'device_trust_state',
            'device_trusted_at',
            'device_blocked_at',
        ])
        second.invalidate_recordset(['device_trust_state', 'device_trusted_at'])

        self.assertEqual(second.device_trust_state, 'trusted')
        self.assertTrue(second.device_trusted_at)
        self.assertEqual(first.device_trust_state, 'pending_trust')
        self.assertFalse(first.device_trusted_at)
        self.assertFalse(first.device_blocked_at)
        self.assertEqual(first.state, 'active')

        controller = self._controller_for_session(first)
        with self.assertRaises(AccessError):
            controller._require_trusted_mobile_auth()

    def test_trusting_same_device_for_other_user_does_not_reset_first_user(self):
        Session = self.env['acpec.mobile.session'].sudo()
        first_user = self._create_mobile_user('shared-device-user-a-43c@example.com')
        second_user = self._create_mobile_user('shared-device-user-b-43c@example.com')
        device_uid = 'ft-shared-device-43c'

        first = Session.create_for_user(first_user, {
            'device_uid': device_uid,
            'platform': 'android',
        })['session']
        first.action_trust_device()

        second = Session.create_for_user(second_user, {
            'device_uid': device_uid,
            'platform': 'android',
        })['session']
        second.action_trust_device()

        first.invalidate_recordset(['device_trust_state', 'device_trusted_at'])
        second.invalidate_recordset(['device_trust_state', 'device_trusted_at'])

        self.assertEqual(first.device_trust_state, 'trusted')
        self.assertTrue(first.device_trusted_at)
        self.assertEqual(second.device_trust_state, 'trusted')
        self.assertTrue(second.device_trusted_at)

    def test_trusting_new_device_does_not_unblock_blocked_device(self):
        user = self._create_mobile_user('blocked-device-single-trust-43c@example.com')
        Session = self.env['acpec.mobile.session'].sudo()

        blocked = Session.create_for_user(user, {
            'device_uid': 'ft-blocked-single-trust-a-43c',
            'platform': 'android',
        })['session']
        blocked.action_trust_device()
        self.env['acpec.mobile.device.trust.wizard'].create({
            'session_id': blocked.id,
            'operation': 'block',
            'reason': 'F2N blocage device fixture',
        }).action_confirm()
        blocked.invalidate_recordset(['state', 'device_trust_state', 'device_blocked_at'])

        self.assertEqual(blocked.device_trust_state, 'blocked')
        self.assertTrue(blocked.device_blocked_at)
        self.assertEqual(blocked.state, 'revoked')

        new_device = Session.create_for_user(user, {
            'device_uid': 'ft-blocked-single-trust-b-43c',
            'platform': 'android',
        })['session']
        new_device.action_trust_device()

        blocked.invalidate_recordset(['state', 'device_trust_state', 'device_blocked_at'])
        new_device.invalidate_recordset(['device_trust_state'])

        self.assertEqual(new_device.device_trust_state, 'trusted')
        self.assertEqual(blocked.device_trust_state, 'blocked')
        self.assertTrue(blocked.device_blocked_at)
        self.assertEqual(blocked.state, 'revoked')

    def test_trust_device_rejects_two_target_devices_for_same_user(self):
        user = self._create_mobile_user('ambiguous-single-trust-43c@example.com')
        Session = self.env['acpec.mobile.session'].sudo()

        first = Session.create_for_user(user, {
            'device_uid': 'ft-ambiguous-single-trust-a-43c',
            'platform': 'android',
        })['session']
        second = Session.create_for_user(user, {
            'device_uid': 'ft-ambiguous-single-trust-b-43c',
            'platform': 'android',
        })['session']

        with self.assertRaises(UserError):
            (first | second).action_trust_device()

        first.invalidate_recordset(['device_trust_state'])
        second.invalidate_recordset(['device_trust_state'])

        self.assertEqual(first.device_trust_state, 'pending_trust')
        self.assertEqual(second.device_trust_state, 'pending_trust')

    def test_direct_write_cannot_create_two_trusted_devices_for_same_user(self):
        user = self._create_mobile_user('direct-write-single-trust-43c@example.com')
        Session = self.env['acpec.mobile.session'].sudo()

        first = Session.create_for_user(user, {
            'device_uid': 'ft-direct-single-trust-a-43c',
            'platform': 'android',
        })['session']
        second = Session.create_for_user(user, {
            'device_uid': 'ft-direct-single-trust-b-43c',
            'platform': 'android',
        })['session']

        first.action_trust_device()

        with self.assertRaises(UserError):
            second.write({
                'device_trust_state': 'trusted',
                'device_trusted_at': fields.Datetime.now(),
            })

        first.invalidate_recordset(['device_trust_state'])
        second.invalidate_recordset(['device_trust_state'])

        self.assertEqual(first.device_trust_state, 'trusted')
        self.assertEqual(second.device_trust_state, 'pending_trust')

    def test_regular_internal_user_cannot_change_device_trust(self):
        session = self._create_session()
        regular_user = self._create_regular_internal_user()

        with self.assertRaises(AccessError):
            session.with_user(regular_user).action_trust_device()

        with self.assertRaises(AccessError):
            session.with_user(regular_user).action_open_block_device_wizard()

        with self.assertRaises(AccessError):
            session.with_user(regular_user).action_open_reset_device_trust_wizard()

    def test_session_views_expose_device_trust_backoffice_controls(self):
        list_arch = self.env.ref('acpec_mobile_auth.view_acpec_mobile_session_tree').arch_db
        form_arch = self.env.ref('acpec_mobile_auth.view_acpec_mobile_session_form').arch_db

        self.assertIn('device_uid', list_arch)
        self.assertIn('device_trust_state', list_arch)

        self.assertIn('action_trust_device', form_arch)
        self.assertIn('action_open_block_device_wizard', form_arch)
        self.assertIn('action_open_reset_device_trust_wizard', form_arch)
        self.assertIn('device_trust_state', form_arch)
        self.assertIn('device_trusted_at', form_arch)
        self.assertIn('device_blocked_at', form_arch)
        self.assertIn('device_trust_note', form_arch)
        self.assertIn('acpec_mobile_auth.group_mobile_auth_admin', form_arch)

    def test_mobile_identity_fields_are_available_for_device_worklist(self):
        user = self._create_mobile_user(
            'Client mobile Test 032',
            phone='21000008',
        )

        token_data = self.env['acpec.mobile.session'].sudo().create_for_user(user, {
            'device_uid': 'device-label-32b',
            'device_name': 'Android 32B',
            'platform': 'android',
        })
        session = token_data['session']
        session.invalidate_recordset(['mobile_phone', 'mobile_user_label'])

        self.assertEqual(session.mobile_phone, '21000008')
        self.assertEqual(session.mobile_user_label, 'Client mobile Test 032 - 21000008')

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

        latest.sudo().with_context(
            acpec_mobile_session_internal_write=True,
        ).write({
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
        self.assertIn(('user_id.acpec_mobile_only', '=', True), domain)
        self.assertIn(('user_id.acpec_mobile_state', 'in', ['approved', 'self_registered']), domain)

        self.assertEqual(context.get('search_default_approval_candidate'), 1)
        self.assertEqual(context.get('search_default_group_by_mobile_user_label'), 1)
        self.assertEqual(
            action.search_view_id,
            self.env.ref('acpec_mobile_auth.view_acpec_mobile_session_search'),
        )

    def test_create_for_user_rotates_prior_active_session_for_stable_device_uid(self):
        user = self._create_mobile_user('session-lifecycle-32d@example.com')
        Session = self.env['acpec.mobile.session'].sudo()

        first = Session.create_for_user(user, {
            'device_uid': 'ft-android-session-lifecycle-32d',
            'device_name': 'Android 32D',
            'platform': 'android',
        })['session']
        second = Session.create_for_user(user, {
            'device_uid': 'ft-android-session-lifecycle-32d',
            'device_name': 'Android 32D',
            'platform': 'android',
        })['session']

        first.invalidate_recordset([
            'state',
            'rotated_at',
            'rotated_to_session_id',
            'refresh_grace_until',
            'refresh_grace_used_at',
            'is_device_approval_candidate',
        ])
        second.invalidate_recordset([
            'state',
            'device_trust_state',
            'is_device_approval_candidate',
        ])

        self.assertEqual(first.state, 'rotated')
        self.assertEqual(first.rotated_to_session_id, second)
        self.assertFalse(first.refresh_grace_until)
        self.assertFalse(first.refresh_grace_used_at)

        self.assertEqual(second.state, 'active')
        self.assertEqual(second.device_trust_state, 'pending_trust')
        self.assertFalse(first.is_device_approval_candidate)
        self.assertTrue(second.is_device_approval_candidate)

    def test_create_for_user_rejects_legacy_flutter_placeholder_uid(self):
        user = self._create_mobile_user('legacy-device-lifecycle-43a@example.com')
        Session = self.env['acpec.mobile.session'].sudo()

        with self.assertRaises(ValidationError):
            Session.create_for_user(user, {
                'device_uid': 'flutter-android-local',
                'device_name': 'Legacy Android',
                'platform': 'android',
            })

        self.assertFalse(Session.search([
            ('user_id', '=', user.id),
            ('state', '=', 'active'),
        ], limit=1))

    def test_create_for_user_does_not_rotate_other_stable_device_uid(self):
        user = self._create_mobile_user('other-device-lifecycle-32d@example.com')
        Session = self.env['acpec.mobile.session'].sudo()

        first = Session.create_for_user(user, {
            'device_uid': 'ft-android-device-a-32d',
            'device_name': 'Android A',
            'platform': 'android',
        })['session']
        second = Session.create_for_user(user, {
            'device_uid': 'ft-android-device-b-32d',
            'device_name': 'Android B',
            'platform': 'android',
        })['session']

        first.invalidate_recordset(['state', 'rotated_to_session_id'])
        second.invalidate_recordset(['state'])

        self.assertEqual(first.state, 'active')
        self.assertFalse(first.rotated_to_session_id)
        self.assertEqual(second.state, 'active')
