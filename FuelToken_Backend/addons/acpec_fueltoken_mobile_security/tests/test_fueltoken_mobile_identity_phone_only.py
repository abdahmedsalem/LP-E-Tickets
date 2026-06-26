# -*- coding: utf-8 -*-
from odoo.exceptions import ValidationError
from odoo.tests.common import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestFuelTokenMobileIdentityPhoneOnly(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.Company = cls.env['res.company'].sudo()
        cls.User = cls.env['res.users'].sudo().with_context(
            acpec_mobile_allow_password_write=True,
            no_reset_password=True,
        )
        cls.Request = cls.env['acpec.mobile.auth.account.request'].sudo()
        cls.fuel_company = cls.env.company.sudo()
        cls.Company.search([
            ('acpec_fueltoken_enabled', '=', True),
            ('id', '!=', cls.fuel_company.id),
        ]).write({'acpec_fueltoken_enabled': False})
        cls.fuel_company.write({
            'acpec_fueltoken_enabled': True,
            'acpec_mobile_auth_enabled': True,
        })
        cls.generic_company = cls.Company.create({
            'name': 'Generic Mobile Auth Company F2A',
            'acpec_mobile_auth_enabled': True,
            'acpec_fueltoken_enabled': False,
        })
        cls.mobile_group_ids = cls._group_ids([
            'base.group_portal',
            'acpec_mobile_auth.group_mobile_auth_user',
        ])

    @classmethod
    def _group_ids(cls, xmlids):
        ids = []
        for xmlid in xmlids:
            group = cls.env.ref(xmlid, raise_if_not_found=False)
            if group:
                ids.append(group.id)
        return ids

    def _mobile_user_vals(self, phone='32345001', login=False, company=False, email=False):
        company = company or self.fuel_company
        return {
            'name': 'Utilisateur mobile FuelToken %s' % phone,
            'login': login or phone,
            'email': email or 'mobile.%s@example.com' % phone,
            'active': True,
            'company_id': company.id,
            'company_ids': [(6, 0, [company.id])],
            'mobile_phone': phone,
            'mobile_only': True,
            'mobile_state': 'self_registered',
            'password': self.User._acpec_mobile_unusable_password(),
            'group_ids': [(6, 0, self.mobile_group_ids)],
        }

    def test_inv_i1_fueltoken_mobile_user_requires_phone_login(self):
        """INV-I1: FuelToken mobile identity is login == mobile_phone == phone."""
        user = self.User.create(self._mobile_user_vals(phone='32345002'))
        self.assertEqual(user.login, '32345002')
        self.assertEqual(user.mobile_phone, '32345002')

        with self.assertRaises(ValidationError):
            self.User.create(self._mobile_user_vals(
                phone='32345003',
                login='mobile.32345003@example.com',
            ))

    def test_inv_i5_fueltoken_mobile_user_requires_one_canonical_phone(self):
        """INV-I5: a FuelToken mobile user has exactly one canonical phone."""
        with self.assertRaises(ValidationError):
            vals = self._mobile_user_vals(phone=False, login='32345004')
            vals.pop('mobile_phone')
            self.User.create(vals)

        with self.assertRaises(ValidationError):
            self.User.create(self._mobile_user_vals(phone='+22232345005', login='+22232345005'))

    def test_generic_mobile_auth_account_request_still_accepts_email(self):
        """acpec_mobile_auth remains generic outside the FuelToken company."""
        rec = self.Request.create({
            'name_display': 'Generic Email Signup',
            'signup_identifier': 'generic.email.f2a@example.com',
            'signup_identifier_type': 'email',
            'email': 'generic.email.f2a@example.com',
            'login': 'generic.email.f2a@example.com',
            'company_id': self.generic_company.id,
        })
        self.assertEqual(rec.signup_identifier_type, 'email')

    def test_inv_i1_fueltoken_account_request_requires_phone_identifier(self):
        """INV-I1: FuelToken signup identifier must be the canonical phone."""
        with self.assertRaises(ValidationError):
            self.Request.create({
                'name_display': 'FuelToken Email Signup',
                'signup_identifier': 'fuel.email.f2a@example.com',
                'signup_identifier_type': 'email',
                'email': 'fuel.email.f2a@example.com',
                'login': 'fuel.email.f2a@example.com',
                'company_id': self.fuel_company.id,
            })

        rec = self.Request.create({
            'name_display': 'FuelToken Phone Signup',
            'signup_identifier': '32345006',
            'signup_identifier_type': 'phone',
            'phone': '32345006',
            'login': '32345006',
            'company_id': self.fuel_company.id,
        })
        self.assertEqual(rec.signup_identifier_type, 'phone')
        self.assertEqual(rec.signup_identifier, '32345006')
        self.assertEqual(rec.login, '32345006')

    def test_inv_i1_fueltoken_account_request_rejects_phone_login_drift(self):
        """INV-I1: signup_identifier, phone and login cannot drift for FuelToken."""
        with self.assertRaises(ValidationError):
            self.Request.create({
                'name_display': 'FuelToken Phone Drift Signup',
                'signup_identifier': '32345007',
                'signup_identifier_type': 'phone',
                'phone': '32345007',
                'login': '32345008',
                'company_id': self.fuel_company.id,
            })
