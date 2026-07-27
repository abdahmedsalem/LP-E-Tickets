# -*- coding: utf-8 -*-
from odoo.tests.common import TransactionCase, tagged


def _acpec_test_mobile_phone(label):
    value = 2166136261
    for char in str(label):
        value ^= ord(char)
        value = (value * 16777619) % 10000000
    return "3%07d" % value


@tagged('post_install', '-at_install')
class TestMobileOldDeviceReturnLifecycle(TransactionCase):

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

    def _create_mobile_user(self, label, state='self_registered'):
        phone = _acpec_test_mobile_phone(label)
        Users = self.env['res.users'].sudo().with_context(
            acpec_mobile_allow_password_write=True,
            no_reset_password=True,
        )
        return Users.create({
            'name': label,
            'login': phone,
            'mobile_phone': phone,
            'active': True,
            'acpec_mobile_only': True,
            'acpec_mobile_state': state,
            'password': Users._acpec_mobile_unusable_password(),
            'group_ids': [(6, 0, self._group_ids())],
        })

    def _create_session(self, user, device_uid):
        return self.env['acpec.mobile.session'].sudo().create_for_user(user, {
            'device_uid': device_uid,
            'device_name': device_uid,
            'platform': 'android',
            'app_version': 'test-f2k',
        })['session']

    def test_f2k_old_pending_device_can_be_reapproved_and_replaces_current_device(self):
        user = self._create_mobile_user(
            'f2k-old-device-return',
            state='self_registered',
        )
        original_user_id = user.id
        original_partner = user.partner_id
        original_phone = user.acpec_mobile_phone

        old_session = self._create_session(
            user,
            'ft-f2k-old-device-a',
        )
        old_device = old_session.device_id

        old_device.action_trust_device()
        old_session.invalidate_recordset(['state', 'device_trust_state', 'device_trusted_at'])
        old_device.invalidate_recordset(['trust_state', 'trusted_at', 'blocked_at'])

        self.assertEqual(old_session.state, 'active')
        self.assertEqual(old_session.device_id, old_device)
        self.assertEqual(old_session.device_trust_state, 'trusted')
        self.assertEqual(old_device.trust_state, 'trusted')
        self.assertTrue(old_device.trusted_at)

        new_session = self._create_session(
            user,
            'ft-f2k-new-device-b',
        )
        new_device = new_session.device_id

        new_session.invalidate_recordset(['state', 'device_trust_state', 'device_trusted_at'])
        old_session.invalidate_recordset(['state', 'device_trust_state', 'device_trusted_at'])
        old_device.invalidate_recordset(['trust_state', 'trusted_at', 'blocked_at'])
        new_device.invalidate_recordset(['trust_state', 'trusted_at', 'blocked_at'])

        self.assertEqual(new_session.state, 'active')
        self.assertEqual(new_session.device_trust_state, 'pending_trust')
        self.assertEqual(new_device.trust_state, 'pending_trust')
        self.assertEqual(old_session.device_trust_state, 'trusted')
        self.assertEqual(old_device.trust_state, 'trusted')

        new_device.action_trust_device()

        old_session.invalidate_recordset(['state', 'device_trust_state', 'device_trusted_at'])
        new_session.invalidate_recordset(['state', 'device_trust_state', 'device_trusted_at'])
        old_device.invalidate_recordset(['trust_state', 'trusted_at', 'blocked_at'])
        new_device.invalidate_recordset(['trust_state', 'trusted_at', 'blocked_at'])

        self.assertEqual(new_session.state, 'active')
        self.assertEqual(new_session.device_trust_state, 'trusted')
        self.assertEqual(new_device.trust_state, 'trusted')
        self.assertTrue(new_device.trusted_at)

        self.assertEqual(old_session.state, 'active')
        self.assertEqual(old_session.device_trust_state, 'pending_trust')
        self.assertEqual(old_device.trust_state, 'pending_trust')
        self.assertFalse(old_device.trusted_at)

        # Ancien device retrouvé : ré-approbation BO normale.
        old_device.action_trust_device()

        old_session.invalidate_recordset(['state', 'device_trust_state', 'device_trusted_at'])
        new_session.invalidate_recordset(['state', 'device_trust_state', 'device_trusted_at'])
        old_device.invalidate_recordset(['trust_state', 'trusted_at', 'blocked_at'])
        new_device.invalidate_recordset(['trust_state', 'trusted_at', 'blocked_at'])

        self.assertEqual(old_session.state, 'active')
        self.assertEqual(old_session.device_trust_state, 'trusted')
        self.assertEqual(old_device.trust_state, 'trusted')
        self.assertTrue(old_device.trusted_at)

        self.assertEqual(new_session.state, 'active')
        self.assertEqual(new_session.device_trust_state, 'pending_trust')
        self.assertEqual(new_device.trust_state, 'pending_trust')
        self.assertFalse(new_device.trusted_at)

        user.invalidate_recordset(['login', 'acpec_mobile_phone', 'partner_id', 'acpec_mobile_state'])
        self.assertEqual(user.id, original_user_id)
        self.assertEqual(user.partner_id, original_partner)
        self.assertEqual(user.login, original_phone)
        self.assertEqual(user.acpec_mobile_phone, original_phone)
        self.assertEqual(user.acpec_mobile_state, 'self_registered')

    def test_f2k_relogin_from_returned_old_device_reuses_durable_device_and_trust(self):
        user = self._create_mobile_user(
            'f2k-old-device-relogin',
            state='self_registered',
        )

        old_session = self._create_session(
            user,
            'ft-f2k-returned-device-a',
        )
        old_device = old_session.device_id
        old_device.action_trust_device()

        new_session = self._create_session(
            user,
            'ft-f2k-returned-device-b',
        )
        new_device = new_session.device_id
        new_device.action_trust_device()

        old_device.invalidate_recordset(['trust_state', 'trusted_at'])
        new_device.invalidate_recordset(['trust_state', 'trusted_at'])

        self.assertEqual(old_device.trust_state, 'pending_trust')
        self.assertEqual(new_device.trust_state, 'trusted')

        old_device.action_trust_device()

        returned_session = self._create_session(
            user,
            'ft-f2k-returned-device-a',
        )

        returned_session.invalidate_recordset(['state', 'device_id', 'device_trust_state', 'device_trusted_at'])
        old_device.invalidate_recordset(['trust_state', 'trusted_at'])
        new_device.invalidate_recordset(['trust_state', 'trusted_at'])

        self.assertEqual(returned_session.state, 'active')
        self.assertEqual(returned_session.device_id, old_device)
        self.assertEqual(returned_session.device_trust_state, 'trusted')
        self.assertEqual(old_device.trust_state, 'trusted')
        self.assertEqual(new_device.trust_state, 'pending_trust')
        self.assertFalse(new_device.trusted_at)
