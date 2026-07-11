# -*- coding: utf-8 -*-
from unittest.mock import patch

from dateutil.relativedelta import relativedelta

from odoo import fields
from odoo.exceptions import AccessError
from odoo.tests.common import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestOtpRuntimeGuardsM23C3(TransactionCase):

    def setUp(self):
        super().setUp()

        self.Otp = self.env['acpec.mobile.auth.otp']
        self.Bucket = self.env[
            'acpec.mobile.auth.otp.verify.bucket'
        ]

        Users = self.env['res.users'].sudo().with_context(
            no_reset_password=True,
        )
        self.mobile_admin = Users.create({
            'name': 'Mobile Auth Admin M23C3',
            'login': 'mobile-auth-admin-m23c3@example.com',
            'email': 'mobile-auth-admin-m23c3@example.com',
            'group_ids': [(6, 0, [
                self.env.ref('base.group_user').id,
                self.env.ref(
                    'acpec_mobile_auth.group_mobile_auth_admin'
                ).id,
            ])],
        })

    def _challenge_vals(self, suffix='base'):
        salt = 'salt-m23c3-%s' % suffix

        return {
            'identifier': '39992331',
            'mobile': '39992331',
            'request_ip': '10.43.23.3',
            'otp_hash': self.Otp._hash_otp(
                '123456',
                salt,
            ),
            'salt': salt,
            'purpose': 'register',
            'expires_at': (
                fields.Datetime.now()
                + relativedelta(minutes=5)
            ),
            'max_attempts': 5,
            'state': 'pending',
        }

    def _create_internal_challenge(self, suffix='base'):
        return self.Otp._create_internal(
            self._challenge_vals(suffix=suffix)
        )

    def _bucket_vals(self, suffix='base'):
        return {
            'scope': 'identifier',
            'purpose': 'login',
            'key': 'm23c3-bucket-%s' % suffix,
        }

    def _create_internal_bucket(self, suffix='base'):
        return self.Bucket._create_internal(
            self._bucket_vals(suffix=suffix)
        )

    def test_m23c3_acl_models_are_read_only(self):
        group = self.env.ref(
            'acpec_mobile_auth.group_mobile_auth_admin'
        )

        for model_name in (
            'acpec.mobile.auth.otp',
            'acpec.mobile.auth.otp.verify.bucket',
        ):
            access = self.env['ir.model.access'].sudo().search([
                ('model_id.model', '=', model_name),
                ('group_id', '=', group.id),
            ], limit=1)

            self.assertTrue(access)
            self.assertTrue(access.perm_read)
            self.assertFalse(access.perm_create)
            self.assertFalse(access.perm_write)
            self.assertFalse(access.perm_unlink)

    def test_m23c3_challenge_create_requires_sudo_and_context(self):
        with self.assertRaises(AccessError):
            self.Otp.sudo().create(
                self._challenge_vals('create-no-context')
            )

        with self.assertRaises(AccessError):
            self.Otp.with_user(
                self.mobile_admin
            ).with_context(
                acpec_mobile_otp_internal_create=True,
            ).create(
                self._challenge_vals('create-no-sudo')
            )

        challenge = self.Otp.sudo().with_context(
            acpec_mobile_otp_internal_create=True,
        ).create(
            self._challenge_vals('create-allowed')
        )

        self.assertTrue(challenge)

    def test_m23c3_challenge_context_does_not_leak(self):
        challenge = self._create_internal_challenge(
            'context-leak'
        )

        self.assertFalse(
            challenge.env.context.get(
                'acpec_mobile_otp_internal_create'
            )
        )
        self.assertFalse(
            challenge.env.context.get(
                'acpec_mobile_otp_internal_write'
            )
        )
        self.assertFalse(
            challenge.env.context.get(
                'acpec_mobile_otp_internal_purge'
            )
        )

        with self.assertRaises(AccessError):
            challenge.write({'state': 'cancelled'})

    def test_m23c3_challenge_write_requires_sudo_and_context(self):
        challenge = self._create_internal_challenge('write')

        with self.assertRaises(AccessError):
            challenge.sudo().write({
                'state': 'cancelled',
            })

        with self.assertRaises(AccessError):
            challenge.with_user(
                self.mobile_admin
            ).with_context(
                acpec_mobile_otp_internal_write=True,
            ).write({
                'state': 'cancelled',
            })

        challenge._write_internal({
            'state': 'cancelled',
        })
        challenge.invalidate_recordset(['state'])

        self.assertEqual(challenge.state, 'cancelled')

    def test_m23c3_challenge_unlink_requires_internal_purge(self):
        challenge = self._create_internal_challenge('purge')
        challenge_id = challenge.id

        with self.assertRaises(AccessError):
            challenge.sudo().unlink()

        with self.assertRaises(AccessError):
            challenge.with_user(
                self.mobile_admin
            ).with_context(
                acpec_mobile_otp_internal_purge=True,
            ).unlink()

        challenge.sudo().with_context(
            acpec_mobile_otp_internal_purge=True,
        ).unlink()

        self.assertFalse(
            self.Otp.sudo().browse(challenge_id).exists()
        )

    def test_m23c3_request_and_verify_use_internal_mutations(self):
        with patch.object(
            type(self.Otp),
            '_new_code',
            return_value='123456',
        ), patch.object(
            type(self.Otp),
            '_send_otp_code',
            return_value=True,
        ):
            challenge, code = self.Otp.sudo().request_otp(
                '39992332',
                purpose='register',
                request_ip='10.43.23.32',
            )

        self.assertEqual(code, '123456')
        self.assertEqual(challenge.state, 'pending')

        challenge.verify(
            '123456',
            request_ip='10.43.23.32',
        )
        challenge.invalidate_recordset([
            'state',
            'verified_at',
        ])

        self.assertEqual(challenge.state, 'verified')
        self.assertTrue(challenge.verified_at)

    def test_m23c3_bucket_create_and_write_require_guards(self):
        with self.assertRaises(AccessError):
            self.Bucket.sudo().create(
                self._bucket_vals('create-no-context')
            )

        with self.assertRaises(AccessError):
            self.Bucket.with_user(
                self.mobile_admin
            ).with_context(
                acpec_mobile_otp_bucket_internal_create=True,
            ).create(
                self._bucket_vals('create-no-sudo')
            )

        bucket = self._create_internal_bucket('write')

        self.assertFalse(
            bucket.env.context.get(
                'acpec_mobile_otp_bucket_internal_create'
            )
        )

        with self.assertRaises(AccessError):
            bucket.sudo().write({
                'failed_count': 1,
            })

        with self.assertRaises(AccessError):
            bucket.with_user(
                self.mobile_admin
            ).with_context(
                acpec_mobile_otp_bucket_internal_write=True,
            ).write({
                'failed_count': 1,
            })

        bucket._write_internal({
            'failed_count': 1,
            'last_failed_at': fields.Datetime.now(),
        })
        bucket.invalidate_recordset([
            'failed_count',
            'last_failed_at',
        ])

        self.assertEqual(bucket.failed_count, 1)
        self.assertTrue(bucket.last_failed_at)

    def test_m23c3_bucket_unlink_requires_internal_purge(self):
        bucket = self._create_internal_bucket('purge')
        bucket_id = bucket.id

        with self.assertRaises(AccessError):
            bucket.sudo().unlink()

        with self.assertRaises(AccessError):
            bucket.with_user(
                self.mobile_admin
            ).with_context(
                acpec_mobile_otp_bucket_internal_purge=True,
            ).unlink()

        bucket.sudo().with_context(
            acpec_mobile_otp_bucket_internal_purge=True,
        ).unlink()

        self.assertFalse(
            self.Bucket.sudo().browse(bucket_id).exists()
        )

    def test_m23c3_otp_views_are_read_only(self):
        list_arch = self.env.ref(
            'acpec_mobile_auth_otp.'
            'view_acpec_mobile_auth_otp_tree'
        ).arch_db
        form_arch = self.env.ref(
            'acpec_mobile_auth_otp.'
            'view_acpec_mobile_auth_otp_form'
        ).arch_db

        self.assertIn(
            '<list create="0" edit="0" delete="0">',
            list_arch,
        )
        self.assertIn(
            '<form create="0" edit="0" delete="0">',
            form_arch,
        )

        self.assertNotIn('otp_hash', form_arch)
        self.assertNotIn('salt', form_arch)
