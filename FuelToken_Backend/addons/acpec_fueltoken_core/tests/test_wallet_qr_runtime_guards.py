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
        return self.Qr.with_context(allow_fuel_qr_create=True).create({
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

        qr = self.Qr.with_context(allow_fuel_qr_create=True).create({
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

        # This intentionally uses incomplete QR line values. The purpose of
        # this test is only to prove that the M21-B runtime guard is bypassed
        # by the explicit internal context. A real QR line is created by
        # issue_from_available(), where face_line/purchase lineage is present.
        with self.assertRaises(Exception) as caught:
            with self.env.cr.savepoint():
                self.QrLine.with_context(allow_fuel_qr_line_create=True).create(vals)
        self.assertNotIsInstance(caught.exception, UserError)

    def test_m21b_qr_unlink_requires_internal_context(self):
        qr = self._qr()

        with self.assertRaises(UserError):
            qr.unlink()

        qr.with_context(allow_fuel_qr_unlink=True).unlink()
        self.assertFalse(qr.exists())

    def test_m21b2_qr_write_state_requires_internal_context(self):
        qr = self._qr()

        with self.assertRaises(ValidationError):
            qr.write({'state': 'blocked'})

        qr.with_context(allow_fuel_qr_state_update=True).write({'state': 'blocked'})
        self.assertEqual(qr.state, 'blocked')

    def test_m21b2_qr_write_economic_fields_rejects_state_context(self):
        parent = self._qr()
        child = self.Qr.with_context(allow_fuel_qr_create=True).create({
            'wallet_id': self._wallet().id,
            'parent_id': parent.id,
        })

        with self.assertRaises(ValidationError):
            child.write({'parent_id': False})

        with self.assertRaises(ValidationError):
            child.with_context(allow_fuel_qr_state_update=True).write({'parent_id': False})

    def test_m21b2_qr_write_economic_context_is_internal_only(self):
        qr = self._qr()

        with self.assertRaises(ValidationError):
            qr.write({'request_hash': 'm21b2-direct'})

        qr.with_context(allow_fuel_qr_economic_update=True).write({
            'request_hash': 'm21b2-internal',
        })
        self.assertEqual(qr.request_hash, 'm21b2-internal')
