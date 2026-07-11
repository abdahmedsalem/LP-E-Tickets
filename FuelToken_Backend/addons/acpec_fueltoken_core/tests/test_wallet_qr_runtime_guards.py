# -*- coding: utf-8 -*-
import uuid

from odoo.exceptions import UserError, ValidationError
from odoo.tests import TransactionCase, tagged


@tagged('-at_install', 'post_install')
class TestWalletQrRuntimeGuards(TransactionCase):

    def setUp(self):
        super().setUp()
        self.company = self.env.company
        self.Partner = self.env['res.partner'].sudo()
        self.Wallet = self.env['acpec.fuel.wallet'].sudo()
        self.Qr = self.env['acpec.fuel.qr'].sudo()
        self.QrLine = self.env['acpec.fuel.qr.line'].sudo()

    def _partner(self):
        return self.Partner.create({
            'name': 'M21B Partner %s' % uuid.uuid4().hex[:8],
        })

    def _wallet(self):
        return self.Wallet.get_or_create(self._partner(), self.company)

    def _qr(self):
        return self.Qr._create_internal({
            'wallet_id': self._wallet().id,
        })

    def test_m21b_wallet_create_requires_internal_context_but_get_or_create_is_allowed(self):
        partner = self._partner()

        with self.assertRaises(UserError):
            self.Wallet.create({
                'partner_id': partner.id,
                'company_id': self.company.id,
            })

        wallet = self.Wallet.get_or_create(partner, self.company)
        self.assertTrue(wallet)
        self.assertEqual(wallet.partner_id.id, partner.id)

    def test_m21b_wallet_unlink_requires_internal_context(self):
        wallet = self._wallet()

        with self.assertRaises(UserError):
            wallet.unlink()

        with self.assertRaises(UserError):
            wallet.sudo().with_context(
                allow_fuel_wallet_unlink=True,
            ).unlink()

        wallet._purge_internal()
        self.assertFalse(wallet.exists())

    def test_m21b_qr_create_requires_internal_context(self):
        wallet = self._wallet()

        with self.assertRaises(UserError):
            self.Qr.create({
                'wallet_id': wallet.id,
            })

        qr = self.Qr._create_internal({
            'wallet_id': wallet.id,
        })
        self.assertTrue(qr)
        self.assertTrue(qr.public_code)

    def test_m21b_qr_line_create_requires_internal_context(self):
        qr = self._qr()
        vals = {
            'qr_id': qr.id,
            'face_value': 100,
            'qty': 1,
        }

        with self.assertRaises(UserError):
            self.QrLine.create(vals)

        with self.assertRaises(Exception) as caught:
            with self.env.cr.savepoint():
                self.QrLine._create_internal(vals)
        self.assertNotIsInstance(caught.exception, UserError)

    def test_m21b_qr_unlink_is_forbidden(self):
        qr = self._qr()

        with self.assertRaises(UserError):
            qr.unlink()

        with self.assertRaises(UserError):
            qr.sudo().unlink()

        self.assertTrue(qr.exists())

    def test_m21b2_qr_write_state_requires_internal_helper(self):
        qr = self._qr()

        with self.assertRaises(UserError):
            qr.write({'state': 'blocked'})

        qr._write_state_internal({'state': 'blocked'})
        self.assertEqual(qr.state, 'blocked')

    def test_m21b2_qr_state_helper_rejects_economic_fields(self):
        parent = self._qr()
        child = self.Qr._create_internal({
            'wallet_id': self._wallet().id,
            'parent_id': parent.id,
        })

        with self.assertRaises(UserError):
            child.write({'parent_id': False})

        with self.assertRaises(ValidationError):
            child._write_state_internal({'parent_id': False})

    def test_m21b2_qr_numeric_hash_helper_is_narrow(self):
        qr = self._qr()

        with self.assertRaises(UserError):
            qr.write({'request_hash': 'm21b2-direct'})

        with self.assertRaises(ValidationError):
            qr._write_numeric_hash_internal({
                'request_hash': 'm21b2-internal',
            })

        self.assertFalse(qr.request_hash)
