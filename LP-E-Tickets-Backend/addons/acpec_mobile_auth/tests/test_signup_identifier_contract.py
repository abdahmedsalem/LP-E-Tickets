# -*- coding: utf-8 -*-
from odoo.exceptions import ValidationError
from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_mobile_auth.controllers.api_common import AcpecMobileAuthApiCommon


class TestableAcpecMobileAuthApiCommon(AcpecMobileAuthApiCommon):

    @property
    def env(self):
        return self._test_env


@tagged('post_install', '-at_install')
class TestSignupIdentifierContract(TransactionCase):

    def setUp(self):
        super().setUp()
        self.controller = TestableAcpecMobileAuthApiCommon()
        self.controller._test_env = self.env

    def test_f2b_signup_identifier_fallback_keeps_phone_and_email(self):
        phone_vals = self.controller._parse_signup_identifier('23000001')
        self.assertEqual(phone_vals['signup_identifier_type'], 'phone')
        self.assertEqual(phone_vals['signup_identifier'], '23000001')
        self.assertEqual(phone_vals['login'], '23000001')
        self.assertEqual(phone_vals['phone'], '23000001')
        self.assertFalse(phone_vals['email'])

        email_vals = self.controller._parse_signup_identifier('Generic.F2B@example.com')
        self.assertEqual(email_vals['signup_identifier_type'], 'email')
        self.assertEqual(email_vals['signup_identifier'], 'generic.f2b@example.com')
        self.assertEqual(email_vals['login'], 'generic.f2b@example.com')
        self.assertFalse(email_vals['phone'])
        self.assertEqual(email_vals['email'], 'generic.f2b@example.com')

    def test_f2b_signup_identifier_type_explicit_accepts_matching_values(self):
        phone_vals = self.controller._parse_signup_identifier(
            '33000001',
            signup_identifier_type='phone',
        )
        self.assertEqual(phone_vals['signup_identifier_type'], 'phone')
        self.assertEqual(phone_vals['phone'], '33000001')

        email_vals = self.controller._parse_signup_identifier(
            'explicit.f2b@example.com',
            signup_identifier_type='email',
        )
        self.assertEqual(email_vals['signup_identifier_type'], 'email')
        self.assertEqual(email_vals['email'], 'explicit.f2b@example.com')

    def test_f2b_signup_identifier_type_rejects_contradictions(self):
        with self.assertRaises(ValidationError):
            self.controller._parse_signup_identifier(
                'explicit.f2b@example.com',
                signup_identifier_type='phone',
            )
        with self.assertRaises(ValidationError):
            self.controller._parse_signup_identifier(
                '23000002',
                signup_identifier_type='email',
            )
        with self.assertRaises(ValidationError):
            self.controller._parse_signup_identifier(
                '23000002',
                signup_identifier_type='sms',
            )

    def test_f2b_phone_identity_rejects_non_canonical_formats(self):
        invalid_values = [
            '+22223000001',
            '22223000001',
            '0022223000001',
            '2300 0001',
            '23-00-00-01',
            '59000001',
            '70000001',
            '323420056',
            '3475',
            'abdb7374',
        ]
        for value in invalid_values:
            with self.subTest(value=value):
                with self.assertRaises(ValidationError):
                    self.controller._parse_signup_identifier(value)

    def test_f2b_invalid_email_is_rejected(self):
        with self.assertRaises(ValidationError):
            self.controller._parse_signup_identifier('abdbd@abdc')
