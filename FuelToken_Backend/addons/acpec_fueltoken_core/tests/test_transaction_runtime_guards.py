# -*- coding: utf-8 -*-
import uuid

from odoo.exceptions import UserError
from odoo.tests import TransactionCase, tagged


@tagged('-at_install', 'post_install')
class TestTransactionRuntimeGuards(TransactionCase):

    def setUp(self):
        super().setUp()
        self.company = self.env.company
        self.Partner = self.env['res.partner'].sudo()
        self.Wallet = self.env['acpec.fuel.wallet'].sudo()
        self.Tx = self.env['acpec.fuel.transaction'].sudo()
        self.TxLine = self.env['acpec.fuel.transaction.line'].sudo()

    def _wallet(self):
        partner = self.Partner.create({
            'name': 'M21 Transaction Guard Partner %s' % uuid.uuid4().hex[:8],
        })
        return self.Wallet.get_or_create(partner, self.company)

    def _logged_transaction(self):
        wallet = self._wallet()
        return self.Tx.log(
            'purchase_submitted',
            self.company,
            wallet=wallet,
            lines=[{
                'face_value': 100,
                'qty': 1,
            }],
            note='M21 transaction guard fixture',
            idempotency_key='M21-TX-%s' % uuid.uuid4().hex[:12],
            request_hash='M21-HASH-%s' % uuid.uuid4().hex[:12],
        )

    def test_m21_direct_transaction_create_is_denied_but_log_is_allowed(self):
        wallet = self._wallet()

        with self.assertRaises(UserError):
            self.Tx.create({
                'transaction_type': 'purchase_submitted',
                'company_id': self.company.id,
                'wallet_id': wallet.id,
            })

        tx = self.Tx.log(
            'purchase_submitted',
            self.company,
            wallet=wallet,
            lines=[{
                'face_value': 100,
                'qty': 1,
            }],
            note='M21 log allowed',
            idempotency_key='M21-LOG-%s' % uuid.uuid4().hex[:12],
            request_hash='M21-LOG-HASH-%s' % uuid.uuid4().hex[:12],
        )
        self.assertTrue(tx)
        self.assertTrue(tx.line_ids)
        self.assertEqual(tx.transaction_type, 'purchase_submitted')

    def test_m21_transaction_write_and_unlink_need_internal_context(self):
        tx = self._logged_transaction()

        with self.assertRaises(UserError):
            tx.write({'note': 'direct mutation forbidden'})

        tx.with_context(allow_fuel_transaction_update=True).write({
            'note': 'internal mutation allowed',
        })
        self.assertEqual(tx.note, 'internal mutation allowed')

        with self.assertRaises(UserError):
            tx.unlink()

        tx.with_context(allow_fuel_transaction_unlink=True).unlink()
        self.assertFalse(tx.exists())

    def test_m21_transaction_line_create_write_unlink_need_internal_context(self):
        tx = self._logged_transaction()

        with self.assertRaises(UserError):
            self.TxLine.create({
                'transaction_id': tx.id,
                'face_value': 100,
                'qty': 1,
            })

        line = self.TxLine.with_context(allow_fuel_transaction_line_create=True).create({
            'transaction_id': tx.id,
            'face_value': 100,
            'qty': 1,
        })
        self.assertTrue(line)

        with self.assertRaises(UserError):
            line.write({'qty': 2})

        line.with_context(allow_fuel_transaction_line_update=True).write({'qty': 2})
        self.assertEqual(line.qty, 2)

        with self.assertRaises(UserError):
            line.unlink()

        line.with_context(allow_fuel_transaction_line_unlink=True).unlink()
        self.assertFalse(line.exists())
