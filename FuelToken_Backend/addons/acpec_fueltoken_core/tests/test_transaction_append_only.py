# -*- coding: utf-8 -*-
from odoo.exceptions import UserError
from odoo.tests.common import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestFuelTransactionAppendOnly(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.Transaction = cls.env['acpec.fuel.transaction'].sudo()

    def _make_transaction(self):
        tx = self.Transaction.log(
            'expiration_faces',
            self.env.company,
            lines=[{
                'face_value': 100,
                'qty': 2,
            }],
            note='G2 append-only fixture',
            idempotency_key='G2-TX2',
        )
        self.assertTrue(tx)
        self.assertTrue(tx.line_ids)
        return tx

    def test_g2_transaction_direct_write_is_blocked(self):
        tx = self._make_transaction()

        with self.assertRaises(UserError):
            tx.write({'note': 'Note post-audit interdite hors flux interne'})

        tx.with_context(allow_fuel_transaction_update=True).write({
            'note': 'Note post-audit interne autorisée',
        })
        self.assertEqual(tx.note, 'Note post-audit interne autorisée')

        with self.assertRaises(UserError):
            tx.write({'transaction_type': 'emission_qr'})

        with self.assertRaises(UserError):
            tx.write({'idempotency_key': 'G2-TX2-CHANGED'})

    def test_g2_transaction_internal_context_allows_controlled_update(self):
        tx = self._make_transaction()

        tx.with_context(allow_fuel_transaction_update=True).write({
            'idempotency_key': 'G2-TX2-INTERNAL',
        })

        self.assertEqual(tx.idempotency_key, 'G2-TX2-INTERNAL')

    def test_g2_transaction_unlink_is_blocked_without_internal_context(self):
        tx = self._make_transaction()

        with self.assertRaises(UserError):
            tx.unlink()

        self.assertTrue(tx.exists())

    def test_g2_transaction_line_write_and_unlink_are_blocked(self):
        tx = self._make_transaction()
        line = tx.line_ids[0]

        with self.assertRaises(UserError):
            line.write({'qty': 99})

        with self.assertRaises(UserError):
            line.write({'face_value': 500})

        with self.assertRaises(UserError):
            line.unlink()

        line.invalidate_recordset(['qty', 'face_value'])
        self.assertEqual(line.qty, 2)
        self.assertEqual(line.face_value, 100)
