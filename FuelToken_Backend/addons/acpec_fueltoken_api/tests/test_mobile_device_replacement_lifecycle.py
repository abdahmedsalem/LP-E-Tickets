# -*- coding: utf-8 -*-
from odoo.exceptions import AccessError
from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_mobile_auth.controllers.api_common import AcpecMobileAuthApiCommon


def _acpec_test_mobile_phone(label):
    value = 2166136261
    for char in str(label):
        value ^= ord(char)
        value = (value * 16777619) % 10000000
    return "3%07d" % value


@tagged('post_install', '-at_install')
class TestMobileDeviceReplacementLifecycle(TransactionCase):

    def _base_mobile_group_ids(self):
        xmlids = (
            'base.group_portal',
            'acpec_mobile_auth.group_mobile_auth_user',
        )
        return [
            self.env.ref(xmlid).id
            for xmlid in xmlids
            if self.env.ref(xmlid, raise_if_not_found=False)
        ]

    def _create_self_registered_mobile_user(self, label):
        phone = _acpec_test_mobile_phone(label)
        Users = self.env['res.users'].sudo().with_context(
            acpec_mobile_allow_password_write=True,
            no_reset_password=True,
        )
        return Users.create({
            'name': label,
            'login': phone,
            'mobile_phone': phone,
            'email': label,
            'active': True,
            'mobile_only': True,
            'mobile_state': 'self_registered',
            'password': Users._acpec_mobile_unusable_password(),
            'group_ids': [(6, 0, self._base_mobile_group_ids())],
        })

    def _controller_for_session(self, session):
        controller = AcpecMobileAuthApiCommon()
        controller._test_env = self.env
        controller._get_mobile_session = lambda required=True: session
        return controller

    def _assert_business_access_refused_for_pending_device(self, session):
        controller = self._controller_for_session(session)
        with self.assertRaises(AccessError) as ctx:
            controller._require_trusted_mobile_auth()
        self.assertIn(
            'Device mobile en attente de validation',
            str(ctx.exception),
        )

    def test_f2h_self_registered_user_can_replace_device_without_identity_change(self):
        fuel_group = self.env.ref('acpec_fueltoken_base.group_fuel_user', raise_if_not_found=False)
        station_group = self.env.ref('acpec_fueltoken_base.group_fuel_station', raise_if_not_found=False)
        manager_group = self.env.ref('acpec_fueltoken_base.group_fuel_manager', raise_if_not_found=False)
        self.assertTrue(fuel_group)

        user = self._create_self_registered_mobile_user(
            'f2h-device-replacement-self-registered@example.com'
        )
        original_user_id = user.id
        original_partner = user.partner_id
        original_login = user.login
        original_mobile_phone = user.mobile_phone

        self.assertFalse(fuel_group in user.group_ids)
        if station_group:
            self.assertFalse(station_group in user.group_ids)
        if manager_group:
            self.assertFalse(manager_group in user.group_ids)

        Session = self.env['acpec.mobile.session'].sudo()

        first_session = Session.create_for_user(user, {
            'device_uid': 'ft-f2h-replacement-device-a',
            'device_name': 'Android F2H A',
            'platform': 'android',
            'app_version': 'test-f2h',
        })['session']

        self.assertTrue(first_session.device_id)
        self.assertEqual(first_session.device_trust_state, 'pending_trust')
        self._assert_business_access_refused_for_pending_device(first_session)

        first_session.device_id.action_trust_device()
        first_session.invalidate_recordset([
            'state',
            'device_trust_state',
            'device_trusted_at',
            'is_device_approval_candidate',
        ])
        first_session.device_id.invalidate_recordset(['trust_state', 'trusted_at'])
        user.invalidate_recordset(['group_ids', 'mobile_state', 'login', 'mobile_phone', 'partner_id'])

        self.assertEqual(first_session.state, 'active')
        self.assertEqual(first_session.device_trust_state, 'trusted')
        self.assertEqual(first_session.device_id.trust_state, 'trusted')
        self.assertFalse(first_session.is_device_approval_candidate)
        self.assertEqual(user.mobile_state, 'self_registered')
        self.assertEqual(user.id, original_user_id)
        self.assertEqual(user.partner_id, original_partner)
        self.assertEqual(user.login, original_login)
        self.assertEqual(user.mobile_phone, original_mobile_phone)
        self.assertTrue(fuel_group in user.group_ids)
        if station_group:
            self.assertFalse(station_group in user.group_ids)
        if manager_group:
            self.assertFalse(manager_group in user.group_ids)

        second_session = Session.create_for_user(user, {
            'device_uid': 'ft-f2h-replacement-device-b',
            'device_name': 'Android F2H B',
            'platform': 'android',
            'app_version': 'test-f2h',
        })['session']

        first_session.invalidate_recordset([
            'state',
            'device_trust_state',
            'device_trusted_at',
            'is_device_approval_candidate',
        ])
        second_session.invalidate_recordset([
            'state',
            'device_trust_state',
            'device_trusted_at',
            'is_device_approval_candidate',
        ])

        self.assertNotEqual(first_session.device_id, second_session.device_id)
        self.assertEqual(first_session.state, 'active')
        self.assertEqual(first_session.device_trust_state, 'trusted')
        self.assertEqual(second_session.state, 'active')
        self.assertEqual(second_session.device_trust_state, 'pending_trust')
        self.assertTrue(second_session.is_device_approval_candidate)
        self._assert_business_access_refused_for_pending_device(second_session)

        second_session.device_id.action_trust_device()

        first_session.invalidate_recordset([
            'state',
            'device_trust_state',
            'device_trusted_at',
            'device_blocked_at',
            'is_device_approval_candidate',
        ])
        second_session.invalidate_recordset([
            'state',
            'device_trust_state',
            'device_trusted_at',
            'device_blocked_at',
            'is_device_approval_candidate',
        ])
        first_session.device_id.invalidate_recordset(['trust_state', 'trusted_at', 'blocked_at'])
        second_session.device_id.invalidate_recordset(['trust_state', 'trusted_at', 'blocked_at'])
        user.invalidate_recordset(['group_ids', 'mobile_state', 'login', 'mobile_phone', 'partner_id'])

        self.assertEqual(second_session.device_trust_state, 'trusted')
        self.assertEqual(second_session.device_id.trust_state, 'trusted')
        self.assertTrue(second_session.device_trusted_at)
        self.assertFalse(second_session.device_blocked_at)
        self.assertFalse(second_session.is_device_approval_candidate)

        self.assertEqual(first_session.state, 'active')
        self.assertEqual(first_session.device_trust_state, 'pending_trust')
        self.assertEqual(first_session.device_id.trust_state, 'pending_trust')
        self.assertFalse(first_session.device_trusted_at)
        self.assertFalse(first_session.device_blocked_at)
        # Après approbation du nouveau device, l'ancienne session reste active
        # mais son device est redescendu en pending_trust. Elle peut donc encore
        # apparaître comme candidate BO tant qu'elle est active, mais elle ne doit
        # plus avoir accès aux données métier.
        self.assertTrue(first_session.is_device_approval_candidate)
        self._assert_business_access_refused_for_pending_device(first_session)

        trusted_user = self._controller_for_session(second_session)._require_trusted_mobile_auth()
        self.assertEqual(trusted_user, user.sudo())

        self.assertEqual(user.mobile_state, 'self_registered')
        self.assertEqual(user.id, original_user_id)
        self.assertEqual(user.partner_id, original_partner)
        self.assertEqual(user.login, original_login)
        self.assertEqual(user.mobile_phone, original_mobile_phone)
        self.assertTrue(fuel_group in user.group_ids)
        if station_group:
            self.assertFalse(station_group in user.group_ids)
        if manager_group:
            self.assertFalse(manager_group in user.group_ids)
