# -*- coding: utf-8 -*-
from odoo.tests.common import TransactionCase, tagged


def _acpec_test_mobile_phone(label):
    value = 2166136261
    for char in str(label):
        value ^= ord(char)
        value = (value * 16777619) % 10000000
    return "3%07d" % value


@tagged('post_install', '-at_install')
class TestMobileUserBlockingLifecycle(TransactionCase):

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

    def _create_mobile_user(self, label, state='approved'):
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

    def test_f2i_reactivating_blocked_user_preserves_device_states(self):
        user = self._create_mobile_user(
            'f2i-reactivate-user-preserve-devices@example.com',
            state='approved',
        )
        Session = self.env['acpec.mobile.session'].sudo()

        trusted_session = Session.create_for_user(user, {
            'device_uid': 'ft-f2i-reactivate-trusted-device',
            'platform': 'android',
        })['session']
        trusted_device = trusted_session.device_id
        trusted_device.action_trust_device()

        pending_session = Session.create_for_user(user, {
            'device_uid': 'ft-f2i-reactivate-pending-device',
            'platform': 'android',
        })['session']
        pending_device = pending_session.device_id

        blocked_session = Session.create_for_user(user, {
            'device_uid': 'ft-f2i-reactivate-blocked-device',
            'platform': 'android',
        })['session']
        blocked_device = blocked_session.device_id
        blocked_device.action_block_device()

        trusted_device.invalidate_recordset(['trust_state'])
        pending_device.invalidate_recordset(['trust_state'])
        blocked_device.invalidate_recordset(['trust_state'])
        self.assertEqual(trusted_device.trust_state, 'trusted')
        self.assertEqual(pending_device.trust_state, 'pending_trust')
        self.assertEqual(blocked_device.trust_state, 'blocked')

        user.sudo().write({'acpec_mobile_state': 'blocked'})
        user.sudo().write({'acpec_mobile_state': 'approved'})

        trusted_device.invalidate_recordset(['trust_state'])
        pending_device.invalidate_recordset(['trust_state'])
        blocked_device.invalidate_recordset(['trust_state'])

        self.assertEqual(trusted_device.trust_state, 'trusted')
        self.assertEqual(pending_device.trust_state, 'pending_trust')
        self.assertEqual(blocked_device.trust_state, 'blocked')
