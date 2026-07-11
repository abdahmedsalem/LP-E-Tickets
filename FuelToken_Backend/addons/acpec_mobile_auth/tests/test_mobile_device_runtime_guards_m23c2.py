# -*- coding: utf-8 -*-
from odoo.exceptions import AccessError
from odoo.tests.common import TransactionCase, tagged


def _acpec_test_mobile_phone(label):
    value = 2166136261
    for char in str(label):
        value ^= ord(char)
        value = (value * 16777619) % 10000000
    return '3%07d' % value


@tagged('post_install', '-at_install')
class TestMobileDeviceRuntimeGuardsM23C2(TransactionCase):

    def setUp(self):
        super().setUp()

        Users = self.env['res.users'].sudo().with_context(
            no_reset_password=True,
        )
        group_user = self.env.ref('base.group_user')
        group_admin = self.env.ref(
            'acpec_mobile_auth.group_mobile_auth_admin'
        )
        portal_group = self.env.ref('base.group_portal')
        mobile_group = self.env.ref(
            'acpec_mobile_auth.group_mobile_auth_user'
        )

        self.mobile_admin = Users.create({
            'name': 'Mobile Auth Admin M23C2',
            'login': 'mobile-auth-admin-m23c2@example.com',
            'email': 'mobile-auth-admin-m23c2@example.com',
            'password': 'AdminM23C2!ChangeMe',
            'group_ids': [
                (6, 0, [group_user.id, group_admin.id]),
            ],
        })

        phone = _acpec_test_mobile_phone(
            'mobile-device-runtime-m23c2'
        )
        mobile_users = Users.with_context(
            acpec_mobile_allow_password_write=True,
        )
        self.mobile_user = mobile_users.create({
            'name': 'Mobile Device Runtime M23C2',
            'login': phone,
            'acpec_mobile_phone': phone,
            'active': True,
            'acpec_mobile_only': True,
            'acpec_mobile_state': 'approved',
            'password': (
                mobile_users._acpec_mobile_unusable_password()
            ),
            'group_ids': [
                (6, 0, [portal_group.id, mobile_group.id]),
            ],
        })

    def _device_vals(self, suffix='base'):
        return {
            'user_id': self.mobile_user.id,
            'stable_device_uid': (
                'ft-mobile-device-runtime-m23c2-%s'
                % suffix
            ),
            'device_name': 'Android M23C2 %s' % suffix,
            'platform': 'android',
            'app_version': 'm23c2',
        }

    def _create_internal_device(self, suffix='base'):
        return self.env[
            'acpec.mobile.device'
        ]._create_internal(
            self._device_vals(suffix=suffix)
        )

    def test_m23c2_acl_is_read_only(self):
        group = self.env.ref(
            'acpec_mobile_auth.group_mobile_auth_admin'
        )
        access = self.env['ir.model.access'].sudo().search([
            ('model_id.model', '=', 'acpec.mobile.device'),
            ('group_id', '=', group.id),
        ], limit=1)

        self.assertTrue(access)
        self.assertTrue(access.perm_read)
        self.assertFalse(access.perm_create)
        self.assertFalse(access.perm_write)
        self.assertFalse(access.perm_unlink)

    def test_m23c2_create_requires_sudo_and_internal_context(self):
        Device = self.env['acpec.mobile.device']

        with self.assertRaises(AccessError):
            Device.sudo().create(
                self._device_vals('create-no-context')
            )

        with self.assertRaises(AccessError):
            Device.with_user(
                self.mobile_admin
            ).with_context(
                acpec_mobile_device_internal_create=True,
            ).create(
                self._device_vals('create-no-sudo')
            )

        device = Device.sudo().with_context(
            acpec_mobile_device_internal_create=True,
        ).create(
            self._device_vals('create-allowed')
        )

        self.assertTrue(device)
        self.assertEqual(
            device.stable_device_uid,
            'ft-mobile-device-runtime-m23c2-create-allowed',
        )

    def test_m23c2_runtime_create_does_not_leak_internal_context(self):
        device = self._create_internal_device(
            'context-leak'
        )

        self.assertFalse(
            device.env.context.get(
                'acpec_mobile_device_internal_create'
            )
        )
        self.assertFalse(
            device.env.context.get(
                'acpec_mobile_device_internal_write'
            )
        )
        self.assertFalse(
            device.env.context.get(
                'acpec_mobile_device_internal_purge'
            )
        )

        with self.assertRaises(AccessError):
            device.write({
                'device_name': 'Context leak refused',
            })

    def test_m23c2_write_requires_sudo_and_internal_context(self):
        device = self._create_internal_device('write')

        with self.assertRaises(AccessError):
            device.sudo().write({
                'device_name': 'No internal context',
            })

        with self.assertRaises(AccessError):
            device.with_user(
                self.mobile_admin
            ).with_context(
                acpec_mobile_device_internal_write=True,
            ).write({
                'device_name': 'No sudo',
            })

        device._write_internal({
            'device_name': 'Internal update M23C2',
        })
        device.invalidate_recordset(['device_name'])

        self.assertEqual(
            device.device_name,
            'Internal update M23C2',
        )

    def test_m23c2_backoffice_actions_work_with_read_only_acl(self):
        session = self.env[
            'acpec.mobile.session'
        ].sudo().create_for_user(
            self.mobile_user,
            {
                'device_uid': (
                    'ft-mobile-device-runtime-m23c2-bo'
                ),
                'device_name': 'Android M23C2 BO',
                'platform': 'android',
                'app_version': 'm23c2',
            },
        )['session']
        device = session.device_id

        device.with_user(
            self.mobile_admin
        ).action_trust_device()
        device.invalidate_recordset(
            ['trust_state', 'trusted_by', 'message_ids']
        )

        self.assertEqual(device.trust_state, 'trusted')
        self.assertEqual(
            device.trusted_by,
            self.mobile_admin,
        )
        self.assertTrue(device.message_ids)

        device.with_user(
            self.mobile_admin
        ).action_block_device(
            reason='Blocage runtime M23C2'
        )
        device.invalidate_recordset(
            ['trust_state', 'blocked_by', 'blocked_reason']
        )

        self.assertEqual(device.trust_state, 'blocked')
        self.assertEqual(
            device.blocked_by,
            self.mobile_admin,
        )
        self.assertEqual(
            device.blocked_reason,
            'Blocage runtime M23C2',
        )

        device.with_user(
            self.mobile_admin
        ).action_reset_device_trust(
            reason='Réinitialisation runtime M23C2'
        )
        device.invalidate_recordset(
            ['trust_state', 'blocked_at', 'blocked_by']
        )

        self.assertEqual(
            device.trust_state,
            'pending_trust',
        )
        self.assertFalse(device.blocked_at)
        self.assertFalse(device.blocked_by)

    def test_m23c2_unlink_requires_sudo_and_internal_purge(self):
        Device = self.env['acpec.mobile.device']
        device = self._create_internal_device('purge')

        with self.assertRaises(AccessError):
            device.sudo().unlink()

        with self.assertRaises(AccessError):
            device.with_user(
                self.mobile_admin
            ).with_context(
                acpec_mobile_device_internal_purge=True,
            ).unlink()

        device_id = device.id
        device.sudo().with_context(
            acpec_mobile_device_internal_purge=True,
        ).unlink()

        self.assertFalse(
            Device.sudo().browse(device_id).exists()
        )

    def test_m23c2_device_views_are_read_only(self):
        list_arch = self.env.ref(
            'acpec_mobile_auth.view_acpec_mobile_device_tree'
        ).arch_db
        form_arch = self.env.ref(
            'acpec_mobile_auth.view_acpec_mobile_device_form'
        ).arch_db

        self.assertIn(
            '<list create="0" edit="0" delete="0">',
            list_arch,
        )
        self.assertIn(
            '<form create="0" edit="0" delete="0">',
            form_arch,
        )
        self.assertIn(
            'action_trust_device',
            form_arch,
        )
        self.assertIn(
            'action_open_block_device_wizard',
            form_arch,
        )
        self.assertIn(
            'action_open_reset_device_trust_wizard',
            form_arch,
        )
