# -*- coding: utf-8 -*-
from psycopg2 import IntegrityError

from odoo.exceptions import UserError, ValidationError
from odoo.tests.common import TransactionCase, tagged
from odoo.tools import mute_logger


def _acpec_test_mobile_phone(label):
    """Return a deterministic canonical 8-digit mobile phone for test labels."""
    value = 2166136261
    for char in str(label):
        value ^= ord(char)
        value = (value * 16777619) % 10000000
    return "3%07d" % value


@tagged('post_install', '-at_install')
class TestMobileDeviceModel(TransactionCase):

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
            'mobile_only': True,
            'mobile_state': 'approved',
            'password': user_model._acpec_mobile_unusable_password(),
            'group_ids': [(6, 0, self._group_ids())],
        })

    def _create_device(self, user, stable_device_uid, **extra):
        vals = {
            'user_id': user.id,
            'stable_device_uid': stable_device_uid,
            'device_name': extra.pop('device_name', 'Android F2D'),
            'platform': extra.pop('platform', 'android'),
            'app_version': extra.pop('app_version', 'test'),
        }
        vals.update(extra)
        return self.env['acpec.mobile.device'].sudo().create(vals)

    def test_f2d_mobile_device_can_be_created_for_mobile_user(self):
        user = self._create_mobile_user('f2d-device-create@example.com')
        device = self._create_device(user, 'ft-f2d-device-create')

        self.assertTrue(device)
        self.assertEqual(device.user_id, user)
        self.assertEqual(device.stable_device_uid, 'ft-f2d-device-create')
        self.assertEqual(device.trust_state, 'pending_trust')
        self.assertTrue(device.first_seen_at)
        self.assertTrue(device.last_seen_at)
        self.assertEqual(device.stable_device_uid, 'ft-f2d-device-create')
        self.assertIn('f2d-device-create@example.com', device.name)
        self.assertIn('Android F2D', device.name)

    def test_f2d_mobile_device_unique_per_user_and_stable_uid(self):
        first_user = self._create_mobile_user('f2d-device-unique-a@example.com')
        second_user = self._create_mobile_user('f2d-device-unique-b@example.com')
        stable_uid = 'ft-f2d-device-unique'

        self._create_device(first_user, stable_uid)

        with self.assertRaises(IntegrityError), mute_logger('odoo.sql_db'):
            with self.env.cr.savepoint():
                self._create_device(first_user, stable_uid)
                self.env.flush_all()

        other_user_device = self._create_device(second_user, stable_uid)
        self.assertEqual(other_user_device.user_id, second_user)
        self.assertEqual(other_user_device.stable_device_uid, stable_uid)

    def test_f2d_mobile_device_rejects_unstable_device_uid(self):
        user = self._create_mobile_user('f2d-device-invalid@example.com')

        for stable_uid in (False, '', 'flutter-android-local', 'flutter-ios-local', 'flutter-web-local', 'web-local'):
            with self.assertRaises(ValidationError):
                with self.env.cr.savepoint():
                    self._create_device(user, stable_uid)

    def test_f2d_trusting_device_resets_other_trusted_devices_for_same_user(self):
        user = self._create_mobile_user('f2d-device-single-trust@example.com')
        first = self._create_device(user, 'ft-f2d-device-trusted-a')
        second = self._create_device(user, 'ft-f2d-device-trusted-b')

        first.action_trust_device()
        first.invalidate_recordset(['trust_state', 'trusted_at'])
        self.assertEqual(first.trust_state, 'trusted')
        self.assertTrue(first.trusted_at)

        second.action_trust_device()
        first.invalidate_recordset(['trust_state', 'trusted_at'])
        second.invalidate_recordset(['trust_state', 'trusted_at'])

        self.assertEqual(second.trust_state, 'trusted')
        self.assertTrue(second.trusted_at)
        self.assertEqual(first.trust_state, 'pending_trust')
        self.assertFalse(first.trusted_at)

    def test_f2d_trusting_same_stable_uid_for_other_user_does_not_reset_first_user(self):
        first_user = self._create_mobile_user('f2d-device-shared-a@example.com')
        second_user = self._create_mobile_user('f2d-device-shared-b@example.com')
        stable_uid = 'ft-f2d-device-shared'

        first = self._create_device(first_user, stable_uid)
        second = self._create_device(second_user, stable_uid)

        first.action_trust_device()
        second.action_trust_device()
        first.invalidate_recordset(['trust_state', 'trusted_at'])
        second.invalidate_recordset(['trust_state', 'trusted_at'])

        self.assertEqual(first.trust_state, 'trusted')
        self.assertTrue(first.trusted_at)
        self.assertEqual(second.trust_state, 'trusted')
        self.assertTrue(second.trusted_at)

    def test_f2d_mobile_device_rejects_ambiguous_bulk_trust_for_same_user(self):
        user = self._create_mobile_user('f2d-device-bulk-trust@example.com')
        first = self._create_device(user, 'ft-f2d-device-bulk-a')
        second = self._create_device(user, 'ft-f2d-device-bulk-b')

        with self.assertRaises(UserError):
            (first | second).action_trust_device()

    def test_f2d_mobile_device_views_and_action_exist(self):
        view_xmlids = (
            'acpec_mobile_auth.view_acpec_mobile_device_tree',
            'acpec_mobile_auth.view_acpec_mobile_device_form',
            'acpec_mobile_auth.view_acpec_mobile_device_search',
            'acpec_mobile_auth.menu_mobile_auth_devices',
        )
        for xmlid in view_xmlids:
            self.assertTrue(self.env.ref(xmlid, raise_if_not_found=False), xmlid)

        action = self.env.ref('acpec_mobile_auth.action_acpec_mobile_device', raise_if_not_found=False)
        self.assertTrue(action)
        self.assertEqual(action.res_model, 'acpec.mobile.device')
