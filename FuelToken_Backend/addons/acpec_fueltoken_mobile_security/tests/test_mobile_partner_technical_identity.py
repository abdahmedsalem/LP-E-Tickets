# -*- coding: utf-8 -*-
from odoo.exceptions import ValidationError
from odoo.tests.common import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestFuelTokenMobilePartnerTechnicalIdentity(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.Company = cls.env['res.company'].sudo()
        cls.User = cls.env['res.users'].sudo().with_context(
            acpec_mobile_allow_password_write=True,
            no_reset_password=True,
        )
        cls.Partner = cls.env['res.partner'].sudo()
        cls.fuel_company = cls.env.company.sudo()
        cls.Company.search([
            ('acpec_fueltoken_enabled', '=', True),
            ('id', '!=', cls.fuel_company.id),
        ]).write({'acpec_fueltoken_enabled': False})
        cls.fuel_company.write({
            'acpec_fueltoken_enabled': True,
            'acpec_mobile_auth_enabled': True,
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

    def _mobile_user(self, phone, name='Sidi Mohamed'):
        return self.User.create({
            'name': name,
            'login': phone,
            'active': True,
            'company_id': self.fuel_company.id,
            'company_ids': [(6, 0, [self.fuel_company.id])],
            'mobile_phone': phone,
            'mobile_only': True,
            'mobile_state': 'self_registered',
            'password': self.User._acpec_mobile_unusable_password(),
            'group_ids': [(6, 0, self.mobile_group_ids)],
        })

    def test_patch43m1_exact_mobile_identity_field_names_are_used(self):
        self.assertIn('mobile_only', self.env['res.users']._fields)
        self.assertIn('acpec_is_mobile_partner', self.env['res.partner']._fields)

        partner_fields = self.env['res.partner']._acpec_fueltoken_mobile_partner_identity_fields()
        self.assertEqual(partner_fields, {'name', 'ref', 'acpec_is_mobile_partner'})
        self.assertNotIn('acpec_mobile_only', partner_fields)
        self.assertNotIn('mobile_only', partner_fields)

    def test_patch43m1_mobile_partner_is_canonical_and_technical_on_create(self):
        user = self._mobile_user('38374744', 'Sidi Mohamed')

        self.assertEqual(user.name, '38374744 - Sidi Mohamed')
        self.assertEqual(user.partner_id.name, '38374744 - Sidi Mohamed')
        self.assertEqual(user.partner_id.ref, 'MOB:38374744')
        self.assertTrue(user.partner_id.acpec_is_mobile_partner)

    def test_patch43m1_mobile_partner_sync_does_not_create_partner(self):
        user = self._mobile_user('38374745', 'Sidi Ahmed')
        partner = user.partner_id

        user._sync_acpec_fueltoken_mobile_partner_identity()

        self.assertEqual(user.partner_id, partner)
        self.assertEqual(partner.name, '38374745 - Sidi Ahmed')
        self.assertEqual(partner.ref, 'MOB:38374745')

    def test_patch43m1_mobile_partner_sync_strips_duplicate_phone_prefix(self):
        user = self._mobile_user('38374746', '38374746 - 38374746 - Sidi Ali')

        self.assertEqual(user.name, '38374746 - Sidi Ali')
        self.assertEqual(user.partner_id.name, '38374746 - Sidi Ali')

    def test_patch43m1_direct_partner_technical_identity_write_is_refused(self):
        user = self._mobile_user('38374747', 'Sidi Ely')
        partner = user.partner_id.sudo()

        for vals in (
            {'name': 'Sidi Ely Manual'},
            {'ref': 'MANUAL-REF'},
            {'acpec_is_mobile_partner': False},
        ):
            with self.subTest(vals=vals):
                with self.assertRaises(ValidationError):
                    partner.write(vals)

    def test_patch43m1_direct_partner_non_identity_write_is_allowed(self):
        user = self._mobile_user('38374748', 'Sidi Brahim')
        partner = user.partner_id.sudo()

        partner.write({'phone': '11111111'})
        partner.invalidate_recordset(['phone'])

        self.assertEqual(partner.phone, '11111111')

    def test_patch43m1_generic_partner_is_not_locked(self):
        partner = self.Partner.create({'name': 'Normal Partner'})
        partner.write({
            'name': 'Normal Partner Updated',
            'ref': 'NORMAL-REF',
        })

        self.assertEqual(partner.name, 'Normal Partner Updated')
        self.assertEqual(partner.ref, 'NORMAL-REF')

    def test_patch43m1_direct_user_name_and_mobile_only_write_is_refused(self):
        user = self._mobile_user('38374749', 'Sidi Mokhtar')

        for vals in (
            {'name': 'Sidi Mokhtar Manual'},
            {'mobile_only': False},
        ):
            with self.subTest(vals=vals):
                with self.assertRaises(ValidationError):
                    user.write(vals)

    def test_patch43m1_controlled_phone_change_resyncs_name_and_ref(self):
        user = self._mobile_user('38374750', 'Sidi Abdallahi')

        log = user.action_fueltoken_change_mobile_phone(
            '38374751',
            'Client changed phone number.',
        )
        user.invalidate_recordset(['name', 'login', 'mobile_phone'])
        user.partner_id.invalidate_recordset(['name', 'ref'])

        self.assertEqual(user.login, '38374751')
        self.assertEqual(user.mobile_phone, '38374751')
        self.assertEqual(user.name, '38374751 - Sidi Abdallahi')
        self.assertEqual(user.partner_id.name, '38374751 - Sidi Abdallahi')
        self.assertEqual(user.partner_id.ref, 'MOB:38374751')
        self.assertEqual(log.old_partner_ref, 'MOB:38374750')
        self.assertEqual(log.new_partner_ref, 'MOB:38374751')

    def test_patch43m1_contacts_action_hides_mobile_technical_partners_without_record_rules(self):
        action = self.env.ref('base.action_partner_form')
        self.assertIn('acpec_is_mobile_partner', action.domain)
        self.assertIn('!=', action.domain)

        for xmlid in (
            'acpec_fueltoken_mobile_security.rule_res_users_hide_mobile_only_for_standard_internal',
            'acpec_fueltoken_mobile_security.rule_res_users_fueltoken_mobile_visibility',
            'acpec_fueltoken_mobile_security.rule_res_partner_hide_mobile_technical_partners_for_internal',
            'acpec_fueltoken_mobile_security.rule_res_partner_hide_mobile_for_standard_internal',
            'acpec_fueltoken_mobile_security.rule_res_partner_fueltoken_mobile_visibility',
        ):
            self.assertFalse(self.env.ref(xmlid, raise_if_not_found=False))
