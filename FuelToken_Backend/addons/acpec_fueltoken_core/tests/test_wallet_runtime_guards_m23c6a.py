import uuid

from odoo.exceptions import UserError, ValidationError
from odoo.tests import tagged
from odoo.tests.common import TransactionCase


@tagged('-at_install', 'post_install')
class TestWalletRuntimeGuardsM23C6A(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.Wallet = cls.env['acpec.fuel.wallet']
        cls.Partner = cls.env['res.partner']
        cls.company = cls.env.company

    def _partner(self):
        return self.Partner.sudo().create({
            'name': 'M23C6A Wallet Partner %s' % uuid.uuid4().hex[:8],
        })

    def _wallet(self):
        return self.Wallet.get_or_create(
            self._partner(),
            self.company,
        )

    def test_m23c6a_wallet_acl_is_read_only(self):
        accesses = self.env['ir.model.access'].sudo().search([
            ('model_id.model', '=', 'acpec.fuel.wallet'),
            ('active', '=', True),
        ])

        self.assertTrue(accesses)

        for access in accesses:
            self.assertTrue(access.perm_read)
            self.assertFalse(access.perm_write)
            self.assertFalse(access.perm_create)
            self.assertFalse(access.perm_unlink)

    def test_m23c6a_create_requires_sudo_and_exact_context(self):
        partner = self._partner()
        vals = {
            'partner_id': partner.id,
            'company_id': self.company.id,
        }

        with self.assertRaises(UserError):
            self.Wallet.sudo().create(vals)

        with self.assertRaises(UserError):
            self.Wallet.sudo().with_context(
                allow_fuel_wallet_create=True,
            ).create(vals)

        admin_user = self.env.ref('base.user_admin')
        with self.assertRaises(UserError):
            self.Wallet.with_user(admin_user).with_context(
                acpec_fueltoken_wallet_internal_operation='create',
            ).create(vals)

        wallet = self.Wallet._create_internal(vals)

        self.assertTrue(wallet)
        self.assertEqual(wallet.partner_id, partner)
        self.assertEqual(wallet.company_id, self.company)

    def test_m23c6a_get_or_create_remains_idempotent(self):
        partner = self._partner()

        wallet_1 = self.Wallet.get_or_create(partner, self.company)
        wallet_2 = self.Wallet.get_or_create(partner, self.company)

        self.assertEqual(wallet_1, wallet_2)

        wallets = self.Wallet.sudo().search([
            ('partner_id', '=', partner.id),
            ('company_id', '=', self.company.id),
        ])
        self.assertEqual(len(wallets), 1)

    def test_m23c6a_write_requires_private_helper(self):
        wallet = self._wallet()

        with self.assertRaises(UserError):
            wallet.write({
                'partner_id': wallet.partner_id.id,
            })

        with self.assertRaises(UserError):
            wallet.sudo().with_context(
                acpec_fueltoken_wallet_internal_operation='create',
            ).write({
                'partner_id': wallet.partner_id.id,
            })

        wallet._write_internal({
            'partner_id': wallet.partner_id.id,
        })

        self.assertTrue(wallet.exists())

    def test_m23c6a_economic_identity_and_balance_stay_locked(self):
        wallet = self._wallet()
        other_partner = self._partner()

        with self.assertRaises(ValidationError):
            wallet._write_internal({
                'partner_id': other_partner.id,
            })

        with self.assertRaises(UserError):
            wallet._write_internal({
                'balance': 100,
            })

        self.assertNotEqual(wallet.partner_id, other_partner)

    def test_m23c6a_purge_requires_private_helper(self):
        wallet = self._wallet()

        with self.assertRaises(UserError):
            wallet.unlink()

        with self.assertRaises(UserError):
            wallet.sudo().with_context(
                allow_fuel_wallet_unlink=True,
            ).unlink()

        with self.assertRaises(UserError):
            wallet.sudo().with_context(
                acpec_fueltoken_wallet_internal_operation='write',
            ).unlink()

        wallet._purge_internal()

        self.assertFalse(wallet.exists())

    def test_m23c6a_purge_rejects_wallet_with_qr(self):
        wallet = self._wallet()

        qr = self.env['acpec.fuel.qr'].sudo().with_context(
            allow_fuel_qr_create=True,
        ).create({
            'wallet_id': wallet.id,
        })

        self.assertTrue(qr)

        with self.assertRaises(UserError):
            wallet._purge_internal()

        self.assertTrue(wallet.exists())
        self.assertTrue(qr.exists())
