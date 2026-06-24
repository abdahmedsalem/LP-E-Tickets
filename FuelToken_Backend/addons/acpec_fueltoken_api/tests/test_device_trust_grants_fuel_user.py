# -*- coding: utf-8 -*-
from odoo.tests.common import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestDeviceTrustGrantsFuelUser(TransactionCase):

    def _group_ids(self, xmlids):
        ids = []
        for xmlid in xmlids:
            group = self.env.ref(xmlid, raise_if_not_found=False)
            if group:
                ids.append(group.id)
        return ids

    def _create_self_registered_user(self, mobile_state='self_registered'):
        user_model = self.env['res.users'].sudo().with_context(
            acpec_mobile_allow_password_write=True,
            no_reset_password=True,
        )
        user = user_model.create({
            'name': 'Auto-inscrit 39A',
            'login': 'self.registered.39a@example.com',
            'email': 'self.registered.39a@example.com',
            'active': True,
            'company_id': self.env.company.id,
            'company_ids': [(6, 0, [self.env.company.id])],
            'mobile_phone': '32343939',
            'mobile_only': True,
            'mobile_state': mobile_state,
            'password': user_model._acpec_mobile_unusable_password(),
            'group_ids': [(6, 0, self._group_ids([
                'base.group_portal',
                'acpec_mobile_auth.group_mobile_auth_user',
            ]))],
        })
        user.set_mobile_pin('1234')
        return user

    def test_trusting_self_registered_device_grants_fuel_user(self):
        user = self._create_self_registered_user()
        fuel_group = self.env.ref('acpec_fueltoken_base.group_fuel_user')
        station_group = self.env.ref('acpec_fueltoken_base.group_fuel_station')
        manager_group = self.env.ref('acpec_fueltoken_base.group_fuel_manager')

        self.assertNotIn(fuel_group, user.group_ids)

        token_data = self.env['acpec.mobile.session'].sudo().create_for_user(user, {
            'device_uid': 'self-registered-fuel-user-device-39a',
            'platform': 'android',
        })
        session = token_data['session']
        self.assertEqual(session.device_trust_state, 'pending_trust')

        session.action_trust_device()

        user.invalidate_recordset(['group_ids'])
        session.invalidate_recordset(['device_trust_state'])

        self.assertEqual(session.device_trust_state, 'trusted')
        self.assertIn(fuel_group, user.group_ids)
        self.assertNotIn(station_group, user.group_ids)
        self.assertNotIn(manager_group, user.group_ids)

    def test_trusting_approved_mobile_user_without_fuel_group_grants_fuel_user(self):
        user = self._create_self_registered_user(mobile_state='approved')
        fuel_group = self.env.ref('acpec_fueltoken_base.group_fuel_user')
        station_group = self.env.ref('acpec_fueltoken_base.group_fuel_station')
        manager_group = self.env.ref('acpec_fueltoken_base.group_fuel_manager')

        self.assertNotIn(fuel_group, user.group_ids)

        token_data = self.env['acpec.mobile.session'].sudo().create_for_user(user, {
            'device_uid': 'approved-fuel-user-device-39a',
            'platform': 'android',
        })
        session = token_data['session']
        self.assertEqual(session.device_trust_state, 'pending_trust')

        session.action_trust_device()

        user.invalidate_recordset(['group_ids'])
        session.invalidate_recordset(['device_trust_state'])

        self.assertEqual(session.device_trust_state, 'trusted')
        self.assertIn(fuel_group, user.group_ids)
        self.assertNotIn(station_group, user.group_ids)
        self.assertNotIn(manager_group, user.group_ids)
