from odoo.exceptions import AccessError, UserError, ValidationError
from odoo.tests import tagged
from odoo.tests.common import TransactionCase, new_test_user


@tagged('post_install', '-at_install')
class TestPaymentMethodPresets(TransactionCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.manager = new_test_user(
            cls.env, login='payment_preset_manager',
            groups='base.group_user,acpec_fueltoken_purchase.group_payment_manager',
        )
        cls.reader = new_test_user(
            cls.env, login='payment_preset_reader', groups='base.group_user',
        )
        cls.methods = cls.env['acpec.fuel.payment.method'].with_user(cls.manager)

    def test_activation_requires_code(self):
        method = self.methods.create({
            'name': 'Test', 'code': 'test_activation', 'active': False,
        })
        with self.assertRaises(ValidationError), self.cr.savepoint():
            method.write({'active': True})
        method.write({'merchant_code': '12345', 'active': True})
        self.assertTrue(method.active)
        with self.assertRaises(ValidationError), self.cr.savepoint():
            method.write({'merchant_code': '  '})

    def test_bankily_code_requires_five_or_six_ascii_digits(self):
        methods = self.methods.with_context(active_test=False)
        bankily = methods.search([('code', '=', 'bankily')], limit=1)
        if not bankily:
            bankily = methods.create({
                'name': 'Bankily', 'code': 'bankily', 'active': False,
            })
        bankily.write({'active': False, 'merchant_code': False})

        for invalid_code in ('1234', '1234567', '12A45', '١٢٣٤٥'):
            with self.subTest(merchant_code=invalid_code):
                with self.assertRaises(ValidationError), self.cr.savepoint():
                    bankily.write({'merchant_code': invalid_code})

        bankily.write({'merchant_code': '12345', 'active': True})
        bankily.write({'merchant_code': '123456'})
        self.assertEqual(bankily.merchant_code, '123456')

        other_method = self.methods.create({
            'name': 'Sedad', 'code': 'test_sedad',
            'merchant_code': 'SEDAD-42', 'active': True,
        })
        self.assertEqual(other_method.merchant_code, 'SEDAD-42')

    def test_code_permission_even_with_sudo(self):
        method = self.methods.create({
            'name': 'Test', 'code': 'test_permission', 'active': False,
        })
        with self.assertRaises(AccessError), self.cr.savepoint():
            method.with_user(self.reader).sudo().write({'merchant_code': '12345'})
        with self.assertRaises(AccessError), self.cr.savepoint():
            self.methods.with_user(self.reader).sudo().create({
                'name': 'Forbidden', 'code': 'forbidden_code',
                'merchant_code': '12345',
            })
        method.write({'merchant_code': '67890'})
        self.assertEqual(method.merchant_code, '67890')

    def test_presets_are_disabled_and_idempotent(self):
        codes = ['bankily', 'sedad', 'masrivi', 'masrvi', 'clic', 'click',
                 'bfi_cash', 'bficash', 'bfi-cash']
        methods = self.methods.sudo().with_context(active_test=False)
        # Isolate fixtures within the test transaction.
        methods.search([('code', 'in', codes)]).unlink()
        methods._seed_default_payment_methods()
        records = methods.search([('code', 'in', codes)])
        self.assertEqual(len(records), 5)
        self.assertFalse(any(records.mapped('active')))
        self.assertFalse(any(records.mapped('merchant_code')))
        self.assertTrue(all(records.mapped('image_1920')))
        bankily = records.filtered(lambda item: item.code == 'bankily')
        bankily.with_user(self.manager).write({
            'merchant_code': '12345', 'active': True,
        })
        records.write({'image_1920': False})
        methods._seed_default_payment_methods()
        self.assertTrue(all(records.mapped('image_1920')))
        self.assertEqual(methods.search([('code', 'in', codes)]), records)
        self.assertEqual(bankily.merchant_code, '12345')
        self.assertTrue(bankily.active)

    def test_normalization_on_create_and_write(self):
        method = self.methods.create({
            'name': 'Normalization', 'code': '  TEST_NORMALIZE  ',
            'color_hex': '  #123ABC  ',
        })
        self.assertEqual(method.code, 'test_normalize')
        self.assertEqual(method.color_hex, '#123ABC')
        method.write({'code': '  RENAMED  ', 'color_hex': ' #ABCDEF '})
        self.assertEqual(method.code, 'renamed')
        self.assertEqual(method.color_hex, '#ABCDEF')
        self.assertEqual(self.methods._normalize_code(123), '123')

        with self.assertRaises(ValidationError), self.cr.savepoint():
            method.write({'merchant_code': 12345})
        with self.assertRaises(ValidationError), self.cr.savepoint():
            method.write({'color_hex': 123})

    def test_archived_global_code_still_blocks_duplicate(self):
        archived_method = self.methods.create({
            'name': 'Archived global',
            'code': 'test_archived_global_code',
            'active': False,
            'company_id': False,
        })

        with self.assertRaises(ValidationError), self.cr.savepoint():
            self.methods.create({
                'name': 'Duplicate global',
                'code': archived_method.code,
                'active': False,
                'company_id': False,
            })

    def test_company_override_and_method_lookup(self):
        global_method = self.methods.create({
            'name': 'Global', 'code': 'test_company_scope',
            'merchant_code': '1111', 'active': True, 'company_id': False,
        })
        company_method = self.methods.create({
            'name': 'Company', 'code': global_method.code,
            'merchant_code': '2222', 'active': True,
            'company_id': self.env.company.id,
        })
        available = self.methods.available_for_company(self.env.company)
        self.assertIn(company_method, available)
        self.assertNotIn(global_method, available)
        self.assertEqual(self.methods.find_available_for_company(
            self.env.company, payment_method_code=' TEST_COMPANY_SCOPE ',
        ), company_method)
        self.assertFalse(self.methods.find_available_for_company(
            self.env.company,
            payment_method_id=company_method.id,
            payment_method_code='different_method',
        ))
        self.assertFalse(self.methods.find_available_for_company(
            self.env.company, payment_method_id='invalid',
        ))
        self.assertFalse(self.methods.find_available_for_company(
            self.env.company,
            payment_method_id=0,
            payment_method_code=global_method.code,
        ))
        company_method.write({'active': False})
        self.assertIn(global_method, self.methods.available_for_company(self.env.company))
        self.assertFalse(self.methods.find_available_for_company(
            self.env.company,
            payment_method_id=company_method.id,
            payment_method_code=global_method.code,
        ))

    def test_purchase_snapshot_survives_configuration_changes(self):
        method = self.methods.create({
            'name': 'Original', 'code': 'test_purchase_snapshot',
            'merchant_code': '12345', 'active': True,
        })
        partner = self.env['res.partner'].create({'name': 'Snapshot client'})
        purchase = self.env['acpec.fuel.purchase']._create_internal({
            'partner_id': partner.id, 'company_id': self.env.company.id,
            'payment_method_id': method.id,
            'payment_method_name': 'Forged name',
            'payment_merchant_code': 'forged',
        })
        method.write({'name': 'Changed', 'merchant_code': '67890'})
        self.assertEqual(purchase.payment_method_name, 'Original')
        self.assertEqual(purchase.payment_method_code, 'test_purchase_snapshot')
        self.assertEqual(purchase.payment_merchant_code, '12345')
        with self.assertRaises(UserError), self.cr.savepoint():
            purchase.write({'payment_merchant_code': '67890'})
        with self.assertRaises(UserError), self.cr.savepoint():
            purchase.write({'payment_method_id': False})

    def test_purchase_without_method_keeps_empty_snapshot(self):
        partner = self.env['res.partner'].create({'name': 'No payment method'})
        purchase = self.env['acpec.fuel.purchase']._create_internal({
            'partner_id': partner.id, 'company_id': self.env.company.id,
            'payment_method_name': 'Forged', 'payment_merchant_code': 'forged',
        })
        self.assertFalse(purchase.payment_method_name)
        self.assertFalse(purchase.payment_method_code)
        self.assertFalse(purchase.payment_merchant_code)

    def test_context_defaults_cannot_bypass_code_permission(self):
        with self.assertRaises(AccessError), self.cr.savepoint():
            self.methods.with_user(self.reader).sudo().with_context(
                default_merchant_code='12345',
            ).create({'name': 'Forbidden default', 'code': 'forbidden_default'})
