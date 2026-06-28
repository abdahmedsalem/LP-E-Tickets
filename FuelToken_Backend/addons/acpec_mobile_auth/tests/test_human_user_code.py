# -*- coding: utf-8 -*-
import re

from odoo.exceptions import AccessError, ValidationError
from odoo.tests.common import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestHumanUserCode(TransactionCase):

    def _users_model(self):
        return self.env['res.users'].sudo().with_context(
            acpec_mobile_allow_password_write=True,
            no_reset_password=True,
        )

    def _vals(self, suffix, **extra):
        Users = self._users_model()
        vals = {
            'name': 'Human Code %s' % suffix,
            'login': 'human-code-%s@example.com' % suffix,
            'email': 'human-code-%s@example.com' % suffix,
            'password': Users._acpec_mobile_unusable_password(),
        }
        vals.update(extra)
        return vals

    def test_human_code_is_generated_and_stable(self):
        Users = self._users_model()
        user = Users.create(self._vals('stable'))
        self.assertRegex(user.acpec_human_code, r'^[A-HJ-NP-Z][0-9]{4}$')

        code = user.acpec_human_code
        user.write({'name': 'Human Code Stable Updated'})
        self.assertEqual(user.acpec_human_code, code)

    def test_human_codes_are_unique_in_batch_create(self):
        Users = self._users_model()
        users = Users.create([
            self._vals('batch-a'),
            self._vals('batch-b'),
        ])
        self.assertEqual(len(users.mapped('acpec_human_code')), 2)
        self.assertEqual(len(set(users.mapped('acpec_human_code'))), 2)

    def test_manual_human_code_is_normalized_on_create(self):
        Users = self._users_model()
        user = Users.create(self._vals('manual', acpec_human_code='m9228'))
        self.assertEqual(user.acpec_human_code, 'M9228')

    def test_invalid_manual_human_code_is_rejected(self):
        Users = self._users_model()
        with self.assertRaises(ValidationError):
            Users.create(self._vals('invalid', acpec_human_code='9228'))

    def test_ambiguous_human_code_letters_are_rejected(self):
        Users = self._users_model()
        for code in ('I1234', 'O1234', 'i1234', 'o1234'):
            with self.subTest(code=code):
                with self.assertRaises(ValidationError):
                    Users.create(self._vals('ambiguous-%s' % code, acpec_human_code=code))

    def test_human_code_write_is_blocked_without_internal_context(self):
        Users = self._users_model()
        user = Users.create(self._vals('blocked-write'))
        with self.assertRaises(AccessError):
            user.write({'acpec_human_code': 'Z9999'})

    def test_human_code_write_is_allowed_with_internal_context(self):
        Users = self._users_model()
        user = Users.create(self._vals('allowed-write'))
        code = Users._acpec_create_unique_human_code(reserved_codes={user.acpec_human_code})
        user.with_context(acpec_allow_human_code_write=True).write({
            'acpec_human_code': code.lower(),
        })
        self.assertEqual(user.acpec_human_code, code)
