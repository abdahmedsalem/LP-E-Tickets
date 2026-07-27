# -*- coding: utf-8 -*-
import hashlib

from lxml import etree

from odoo.exceptions import AccessError
from odoo.tests.common import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestAccountRequestRuntimeGuardsM23C4(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()

        cls.Request = cls.env[
            'acpec.mobile.auth.account.request'
        ]
        cls.Users = cls.env['res.users'].sudo().with_context(
            no_reset_password=True,
        )

        group_user = cls.env.ref('base.group_user')
        group_admin = cls.env.ref(
            'acpec_mobile_auth.group_mobile_auth_admin'
        )

        cls.mobile_admin = cls.Users.create({
            'name': 'Mobile Auth Admin M23C4',
            'login': 'mobile-auth-admin-m23c4@example.com',
            'email': 'mobile-auth-admin-m23c4@example.com',
            'active': True,
            'group_ids': [
                (6, 0, [group_user.id, group_admin.id]),
            ],
        })

        cls.regular_user = cls.Users.create({
            'name': 'Regular Internal User M23C4',
            'login': 'regular-user-m23c4@example.com',
            'email': 'regular-user-m23c4@example.com',
            'active': True,
            'group_ids': [(6, 0, [group_user.id])],
        })

    def _phone(self, label):
        digest = hashlib.sha256(
            label.encode('utf-8')
        ).hexdigest()
        suffix = int(digest[:8], 16) % 1000000
        return '42%06d' % suffix

    def _request_vals(self, label, user=False):
        phone = self._phone(label)
        vals = {
            'name_display': 'Account Request M23C4 %s' % label,
            'signup_identifier': phone,
            'signup_identifier_type': 'phone',
            'phone': phone,
            'login': phone,
            'company_id': self.env.company.id,
            'state': 'pending',
        }
        if user:
            vals.update({
                'partner_id': user.partner_id.id,
                'user_id': user.id,
            })
        return vals

    def _create_request(self, label, user=False):
        return self.Request._create_internal(
            self._request_vals(label, user=user)
        )

    def _create_mobile_user(self, label):
        phone = self._phone('user-%s' % label)
        portal_group = self.env.ref('base.group_portal')
        mobile_group = self.env.ref(
            'acpec_mobile_auth.group_mobile_auth_user'
        )

        Users = self.Users.with_context(
            acpec_mobile_allow_password_write=True,
            acpec_fueltoken_allow_mobile_identity_initialization=True,
        )
        return Users.create({
            'name': 'Mobile User M23C4 %s' % label,
            'login': phone,
            'email': 'm23c4.%s@example.com' % label,
            'acpec_mobile_phone': phone,
            'company_id': self.env.company.id,
            'company_ids': [(6, 0, [self.env.company.id])],
            'active': True,
            'acpec_mobile_only': True,
            'acpec_mobile_state': 'pending',
            'password': Users._acpec_mobile_unusable_password(),
            'group_ids': [
                (6, 0, [portal_group.id, mobile_group.id]),
            ],
        })

    def test_m23c4_acl_is_read_only(self):
        group = self.env.ref(
            'acpec_mobile_auth.group_mobile_auth_admin'
        )
        access = self.env['ir.model.access'].sudo().search([
            (
                'model_id.model',
                '=',
                'acpec.mobile.auth.account.request',
            ),
            ('group_id', '=', group.id),
        ], limit=1)

        self.assertTrue(access)
        self.assertTrue(access.perm_read)
        self.assertFalse(access.perm_create)
        self.assertFalse(access.perm_write)
        self.assertFalse(access.perm_unlink)

    def test_m23c4_create_requires_sudo_and_exact_context(self):
        vals = self._request_vals('create-guard')

        with self.assertRaises(AccessError):
            self.Request.sudo().create(vals)

        with self.assertRaises(AccessError):
            self.Request.with_user(
                self.regular_user
            ).with_context(
                acpec_mobile_auth_account_request_internal_create=True,
            ).create(vals)

        request_record = self.Request._create_internal(vals)
        self.assertTrue(request_record)

        for key in (
            'acpec_mobile_auth_account_request_internal_create',
            'acpec_mobile_auth_account_request_internal_write',
            'acpec_mobile_auth_account_request_internal_purge',
            'acpec_mobile_auth_account_request_internal_action',
            'acpec_mobile_auth_account_request_action_actor_user_id',
        ):
            self.assertFalse(
                request_record.env.context.get(key)
            )

    def test_m23c4_write_requires_internal_helper(self):
        request_record = self._create_request('write-guard')

        with self.assertRaises(AccessError):
            request_record.sudo().write({
                'note': 'direct write denied',
            })

        request_record._write_internal({
            'note': 'internal write allowed',
        })
        request_record.invalidate_recordset(['note'])
        self.assertEqual(
            request_record.note,
            'internal write allowed',
        )

    def test_m23c4_unlink_requires_internal_purge(self):
        request_record = self._create_request('purge-guard')
        request_id = request_record.id

        with self.assertRaises(AccessError):
            request_record.sudo().unlink()

        request_record._purge_internal()
        self.assertFalse(
            self.Request.sudo().browse(request_id).exists()
        )

    def test_m23c4_backoffice_action_requires_admin_group(self):
        request_record = self._create_request(
            'backoffice-action'
        )

        with self.assertRaises(AccessError):
            request_record.with_user(
                self.regular_user
            ).action_reject(reason='Denied')

        with self.assertRaises(AccessError):
            request_record.sudo().action_reject(
                reason='Sudo alone denied'
            )

        request_record.with_user(
            self.mobile_admin
        ).action_reject(reason='Controlled rejection')

        request_record.invalidate_recordset([
            'state',
            'reviewed_by',
            'rejection_reason',
        ])
        self.assertEqual(request_record.state, 'rejected')
        self.assertEqual(
            request_record.reviewed_by,
            self.mobile_admin,
        )
        self.assertEqual(
            request_record.rejection_reason,
            'Controlled rejection',
        )

    def test_m23c4_internal_api_action_preserves_actor(self):
        request_record = self._create_request(
            'internal-api-action'
        )

        request_record.sudo().with_context(
            acpec_mobile_auth_account_request_internal_action=True,
            acpec_mobile_auth_account_request_action_actor_user_id=(
                self.regular_user.id
            ),
        ).action_reject(reason='Manager API rejection')

        request_record.invalidate_recordset([
            'state',
            'reviewed_by',
        ])
        self.assertEqual(request_record.state, 'rejected')
        self.assertEqual(
            request_record.reviewed_by,
            self.regular_user,
        )

    def test_m23c4_approve_uses_controlled_internal_write(self):
        mobile_user = self._create_mobile_user('approve')
        request_record = self._create_request(
            'approve',
            user=mobile_user,
        )

        request_record.with_user(
            self.mobile_admin
        ).action_approve()

        request_record.invalidate_recordset([
            'state',
            'reviewed_by',
        ])
        mobile_user.invalidate_recordset([
            'active',
            'acpec_mobile_state',
        ])

        self.assertEqual(request_record.state, 'approved')
        self.assertEqual(
            request_record.reviewed_by,
            self.mobile_admin,
        )
        self.assertTrue(mobile_user.active)
        self.assertEqual(
            mobile_user.acpec_mobile_state,
            'approved',
        )

    def test_m23c4_account_request_views_are_read_only(self):
        for xmlid, expected_tag in (
            (
                'acpec_mobile_auth.'
                'view_acpec_mobile_auth_account_request_tree',
                'list',
            ),
            (
                'acpec_mobile_auth.'
                'view_acpec_mobile_auth_account_request_form',
                'form',
            ),
        ):
            view = self.env.ref(xmlid)
            root = etree.fromstring(
                view.arch_db.encode('utf-8')
            )

            self.assertEqual(root.tag, expected_tag)
            self.assertEqual(root.get('create'), '0')
            self.assertEqual(root.get('edit'), '0')
            self.assertEqual(root.get('delete'), '0')
