# -*- coding: utf-8 -*-
from dateutil.relativedelta import relativedelta
from lxml import etree

from odoo import fields
from odoo.exceptions import AccessError
from odoo.tests.common import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestMobileSessionRuntimeGuardsM23C1(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()

        cls.Session = cls.env['acpec.mobile.session']
        cls.mobile_user = cls.env['res.users'].sudo().with_context(
            acpec_mobile_allow_password_write=True,
            no_reset_password=True,
        ).create({
            'name': 'M23-C1 Mobile Session Guards',
            'login': '39992311',
            'acpec_mobile_phone': '39992311',
            'email': 'm23c1-session-guards@example.com',
            'active': True,
            'acpec_mobile_only': True,
            'acpec_mobile_state': 'approved',
            'password': cls.env['res.users']._acpec_mobile_unusable_password(),
            'group_ids': [(6, 0, [
                cls.env.ref('base.group_portal').id,
                cls.env.ref(
                    'acpec_mobile_auth.group_mobile_auth_user'
                ).id,
            ])],
        })

        cls.mobile_admin = cls.env['res.users'].sudo().with_context(
            no_reset_password=True,
        ).create({
            'name': 'M23-C1 Mobile Auth Admin',
            'login': 'm23c1-mobile-auth-admin',
            'email': 'm23c1-mobile-auth-admin@example.com',
            'active': True,
            'group_ids': [(6, 0, [
                cls.env.ref('base.group_user').id,
                cls.env.ref(
                    'acpec_mobile_auth.group_mobile_auth_admin'
                ).id,
            ])],
        })

    def _create_vals(self, suffix):
        now = fields.Datetime.now()

        return {
            'user_id': self.mobile_user.id,
            'access_token_hash': self.Session._hash_token(
                'm23c1-access-%s' % suffix
            ),
            'refresh_token_hash': self.Session._hash_token(
                'm23c1-refresh-%s' % suffix
            ),
            'device_uid': 'ft-m23c1-%s' % suffix,
            'platform': 'android',
            'expires_at': now + relativedelta(minutes=5),
            'refresh_expires_at': now + relativedelta(days=1),
            'state': 'active',
        }

    def _create_runtime_session(self, suffix):
        return self.Session.sudo().create_for_user(
            self.mobile_user,
            {
                'device_uid': 'ft-m23c1-runtime-%s' % suffix,
                'platform': 'android',
            },
        )['session']

    def test_m23c1_acl_is_read_only(self):
        access = self.env.ref(
            'acpec_mobile_auth.access_acpec_mobile_session_admin'
        )

        self.assertTrue(access.perm_read)
        self.assertFalse(access.perm_write)
        self.assertFalse(access.perm_create)
        self.assertFalse(access.perm_unlink)

    def test_m23c1_create_requires_sudo_and_internal_context(self):
        with self.assertRaises(AccessError):
            self.Session.sudo().create(
                self._create_vals('create-no-context')
            )

        with self.assertRaises(AccessError):
            self.Session.with_user(self.mobile_user).with_context(
                acpec_mobile_session_internal_create=True,
            ).create(
                self._create_vals('create-no-sudo')
            )

        session = self.Session.sudo().with_context(
            acpec_mobile_session_internal_create=True,
        ).create(
            self._create_vals('create-allowed')
        )

        self.assertTrue(session)

    def test_m23c1_runtime_create_does_not_leak_internal_context(self):
        session = self._create_runtime_session('context-leak')

        self.assertFalse(
            session.env.context.get(
                'acpec_mobile_session_internal_create'
            )
        )
        self.assertFalse(
            session.env.context.get(
                'acpec_mobile_session_internal_write'
            )
        )

        with self.assertRaises(AccessError):
            session.write({
                'device_name': 'Direct write refused',
            })

    def test_m23c1_write_requires_sudo_and_internal_context(self):
        session = self._create_runtime_session('write')

        with self.assertRaises(AccessError):
            session.sudo().write({
                'device_name': 'No internal context',
            })

        with self.assertRaises(AccessError):
            session.with_user(self.mobile_user).with_context(
                acpec_mobile_session_internal_write=True,
            ).write({
                'device_name': 'Context without sudo',
            })

        session.sudo().with_context(
            acpec_mobile_session_internal_write=True,
        ).write({
            'device_name': 'Internal update',
        })

        session.invalidate_recordset(['device_name'])
        self.assertEqual(session.device_name, 'Internal update')

    def test_m23c1_backoffice_revoke_works_with_read_only_acl(self):
        session = self._create_runtime_session('admin-revoke')

        session.with_user(self.mobile_admin).action_revoke()

        session.invalidate_recordset([
            'state',
            'revoked_at',
        ])

        self.assertEqual(session.state, 'revoked')
        self.assertTrue(session.revoked_at)

    def test_m23c1_unlink_requires_sudo_and_internal_purge(self):
        session = self._create_runtime_session('purge')

        with self.assertRaises(AccessError):
            session.sudo().unlink()

        with self.assertRaises(AccessError):
            session.with_user(self.mobile_user).with_context(
                acpec_mobile_session_internal_purge=True,
            ).unlink()

        session_id = session.id

        session.sudo().with_context(
            acpec_mobile_session_internal_purge=True,
        ).unlink()

        self.assertFalse(
            self.Session.sudo().browse(session_id).exists()
        )

    def test_m23c1_session_views_are_read_only(self):
        list_view = self.env.ref(
            'acpec_mobile_auth.view_acpec_mobile_session_tree'
        )
        form_view = self.env.ref(
            'acpec_mobile_auth.view_acpec_mobile_session_form'
        )

        list_root = etree.fromstring(
            list_view.arch_db.encode('utf-8')
        )
        form_root = etree.fromstring(
            form_view.arch_db.encode('utf-8')
        )

        for root in (list_root, form_root):
            self.assertEqual(root.get('create'), '0')
            self.assertEqual(root.get('edit'), '0')
            self.assertEqual(root.get('delete'), '0')

        note_fields = form_root.xpath(
            "//field[@name='device_trust_note']"
        )

        self.assertEqual(len(note_fields), 1)
        self.assertEqual(note_fields[0].get('readonly'), '1')
