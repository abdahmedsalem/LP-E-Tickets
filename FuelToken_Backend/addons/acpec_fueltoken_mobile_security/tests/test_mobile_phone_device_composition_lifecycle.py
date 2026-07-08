# -*- coding: utf-8 -*-
from odoo.tests.common import TransactionCase, tagged


def _acpec_test_mobile_phone(label):
    value = 2166136261
    for char in str(label):
        value ^= ord(char)
        value = (value * 16777619) % 10000000
    return "3%07d" % value


@tagged('post_install', '-at_install')
class TestMobilePhoneDeviceCompositionLifecycle(TransactionCase):

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
            'app_version': 'test-f2j',
        })['session']

    def _assert_no_user_resolves_old_phone(self, old_phone):
        Users = self.env['res.users'].sudo().with_context(active_test=False)
        self.assertFalse(Users.search([
            '|',
            ('login', '=', old_phone),
            ('acpec_mobile_phone', '=', old_phone),
        ], limit=1))

    def test_f2j_phone_then_device_is_f2g_plus_f2h_composition(self):
        user = self._create_mobile_user(
            'f2j-phone-then-device-composition',
            state='self_registered',
        )
        original_user_id = user.id
        original_partner = user.partner_id
        old_phone = user.acpec_mobile_phone
        new_phone = _acpec_test_mobile_phone('f2j-phone-then-device-new-phone')

        first_session = self._create_session(
            user,
            'ft-f2j-phone-then-device-a',
        )
        first_device = first_session.device_id
        first_device.action_trust_device()
        first_session.invalidate_recordset(['state', 'device_trust_state'])
        first_device.invalidate_recordset(['trust_state'])

        self.assertEqual(first_session.device_trust_state, 'trusted')
        self.assertEqual(first_device.trust_state, 'trusted')

        log = user.action_fueltoken_change_mobile_phone(
            new_phone,
            'F2J composition: phone then device',
            source='backoffice',
        )

        user.invalidate_recordset(['login', 'acpec_mobile_phone', 'partner_id', 'acpec_mobile_state'])
        first_session.invalidate_recordset(['state', 'revoked_at', 'device_trust_state'])
        first_device.invalidate_recordset(['trust_state'])

        self.assertTrue(log)
        self.assertEqual(user.id, original_user_id)
        self.assertEqual(user.partner_id, original_partner)
        self.assertEqual(user.login, new_phone)
        self.assertEqual(user.acpec_mobile_phone, new_phone)
        self.assertEqual(user.acpec_mobile_state, 'self_registered')
        self._assert_no_user_resolves_old_phone(old_phone)

        # F2G révoque les sessions, mais ne retire pas le trust durable
        # du device si c'est le même user.
        self.assertEqual(first_session.state, 'revoked')
        self.assertTrue(first_session.revoked_at)
        self.assertEqual(first_device.trust_state, 'trusted')

        second_session = self._create_session(
            user,
            'ft-f2j-phone-then-device-b',
        )
        second_device = second_session.device_id

        second_session.invalidate_recordset(['state', 'device_trust_state'])
        first_device.invalidate_recordset(['trust_state'])
        second_device.invalidate_recordset(['trust_state'])

        self.assertEqual(first_device.trust_state, 'trusted')
        self.assertEqual(second_session.device_trust_state, 'pending_trust')
        self.assertEqual(second_device.trust_state, 'pending_trust')

        second_device.action_trust_device()

        first_device.invalidate_recordset(['trust_state', 'trusted_at'])
        second_device.invalidate_recordset(['trust_state', 'trusted_at'])
        second_session.invalidate_recordset(['state', 'device_trust_state'])

        self.assertEqual(second_session.state, 'active')
        self.assertEqual(second_session.device_trust_state, 'trusted')
        self.assertEqual(second_device.trust_state, 'trusted')
        self.assertEqual(first_device.trust_state, 'pending_trust')
        self.assertFalse(first_device.trusted_at)

        user.invalidate_recordset(['login', 'acpec_mobile_phone', 'partner_id', 'acpec_mobile_state'])
        self.assertEqual(user.id, original_user_id)
        self.assertEqual(user.partner_id, original_partner)
        self.assertEqual(user.login, new_phone)
        self.assertEqual(user.acpec_mobile_phone, new_phone)
        self.assertEqual(user.acpec_mobile_state, 'self_registered')

    def test_f2j_device_then_phone_is_f2h_plus_f2g_composition(self):
        user = self._create_mobile_user(
            'f2j-device-then-phone-composition',
            state='self_registered',
        )
        original_user_id = user.id
        original_partner = user.partner_id
        old_phone = user.acpec_mobile_phone
        new_phone = _acpec_test_mobile_phone('f2j-device-then-phone-new-phone')

        first_session = self._create_session(
            user,
            'ft-f2j-device-then-phone-a',
        )
        first_device = first_session.device_id
        first_device.action_trust_device()

        second_session = self._create_session(
            user,
            'ft-f2j-device-then-phone-b',
        )
        second_device = second_session.device_id

        first_device.invalidate_recordset(['trust_state'])
        second_device.invalidate_recordset(['trust_state'])
        second_session.invalidate_recordset(['state', 'device_trust_state'])

        self.assertEqual(first_device.trust_state, 'trusted')
        self.assertEqual(second_device.trust_state, 'pending_trust')
        self.assertEqual(second_session.device_trust_state, 'pending_trust')

        second_device.action_trust_device()

        first_device.invalidate_recordset(['trust_state', 'trusted_at'])
        second_device.invalidate_recordset(['trust_state', 'trusted_at'])
        second_session.invalidate_recordset(['state', 'device_trust_state'])

        self.assertEqual(first_device.trust_state, 'pending_trust')
        self.assertFalse(first_device.trusted_at)
        self.assertEqual(second_device.trust_state, 'trusted')
        self.assertEqual(second_session.device_trust_state, 'trusted')

        log = user.action_fueltoken_change_mobile_phone(
            new_phone,
            'F2J composition: device then phone',
            source='backoffice',
        )

        user.invalidate_recordset(['login', 'acpec_mobile_phone', 'partner_id', 'acpec_mobile_state'])
        second_session.invalidate_recordset(['state', 'revoked_at', 'device_trust_state'])
        first_device.invalidate_recordset(['trust_state'])
        second_device.invalidate_recordset(['trust_state'])

        self.assertTrue(log)
        self.assertEqual(user.id, original_user_id)
        self.assertEqual(user.partner_id, original_partner)
        self.assertEqual(user.login, new_phone)
        self.assertEqual(user.acpec_mobile_phone, new_phone)
        self.assertEqual(user.acpec_mobile_state, 'self_registered')
        self._assert_no_user_resolves_old_phone(old_phone)

        # F2G révoque les sessions actives, mais ne modifie pas le trust durable
        # du nouveau device déjà approuvé par F2H.
        self.assertEqual(second_session.state, 'revoked')
        self.assertTrue(second_session.revoked_at)
        self.assertEqual(first_device.trust_state, 'pending_trust')
        self.assertEqual(second_device.trust_state, 'trusted')

        successor_session = self._create_session(
            user,
            'ft-f2j-device-then-phone-b',
        )
        successor_session.invalidate_recordset(['state', 'device_trust_state'])
        successor_session.device_id.invalidate_recordset(['trust_state'])

        self.assertEqual(successor_session.state, 'active')
        self.assertEqual(successor_session.device_id, second_device)
        self.assertEqual(successor_session.device_trust_state, 'trusted')
        self.assertEqual(second_device.trust_state, 'trusted')

        user.invalidate_recordset(['login', 'acpec_mobile_phone', 'partner_id', 'acpec_mobile_state'])
        self.assertEqual(user.id, original_user_id)
        self.assertEqual(user.partner_id, original_partner)
        self.assertEqual(user.login, new_phone)
        self.assertEqual(user.acpec_mobile_phone, new_phone)
        self.assertEqual(user.acpec_mobile_state, 'self_registered')
