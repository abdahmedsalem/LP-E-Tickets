# -*- coding: utf-8 -*-
from odoo.tests.common import TransactionCase, tagged


def _acpec_test_mobile_phone(label):
    value = 2166136261
    for char in str(label):
        value ^= ord(char)
        value = (value * 16777619) % 10000000
    return "3%07d" % value


@tagged('post_install', '-at_install')
class TestMobileDeviceTrustGrantsFuelUser(TransactionCase):

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

    def _create_mobile_user(self, label):
        phone = _acpec_test_mobile_phone(label)
        user_model = self.env['res.users'].sudo().with_context(
            acpec_mobile_allow_password_write=True,
            no_reset_password=True,
        )
        return user_model.create({
            'name': label,
            'login': phone,
            'mobile_phone': phone,
            'email': label,
            'active': True,
            'acpec_mobile_only': True,
            'acpec_mobile_state': 'self_registered',
            'password': user_model._acpec_mobile_unusable_password(),
            'group_ids': [(6, 0, self._group_ids())],
        })

    def test_f2f_trusting_durable_device_directly_grants_fuel_user_group(self):
        fuel_group = self.env.ref('acpec_fueltoken_base.group_fuel_user', raise_if_not_found=False)
        self.assertTrue(fuel_group)

        user = self._create_mobile_user('f2f-device-direct-fuel-grant@example.com')
        self.assertFalse(fuel_group in user.group_ids)

        session = self.env['acpec.mobile.session'].sudo().create_for_user(user, {
            'device_uid': 'ft-f2f-device-direct-fuel-grant',
            'device_name': 'Android F2F Fuel',
            'platform': 'android',
            'app_version': 'test',
        })['session']

        session.device_id.action_trust_device()
        session.invalidate_recordset(['device_trust_state'])
        user.invalidate_recordset(['group_ids'])

        self.assertEqual(session.device_trust_state, 'trusted')
        self.assertTrue(fuel_group in user.group_ids)
