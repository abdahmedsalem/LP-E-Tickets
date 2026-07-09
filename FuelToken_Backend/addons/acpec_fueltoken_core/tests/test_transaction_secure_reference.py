# -*- coding: utf-8 -*-
import re
from unittest.mock import patch

from odoo.exceptions import UserError
from odoo.tests import TransactionCase, tagged


@tagged('-at_install', 'post_install')
class TestFuelTransactionSecureReference(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.Transaction = cls.env['acpec.fuel.transaction'].sudo()
        cls.operation_ref_pattern = re.compile(r'^TX-\d{8}-\d{6}-\d{12}$')
        cls.name_pattern = re.compile(r'^FTX/\d{4}/\d{6}$')

    def _make_transaction(self, **extra):
        vals = {
            'transaction_type': 'expiration_faces',
            'company_id': self.env.company.id,
            'note': 'Patch43M20-A reference test',
        }
        vals.update(extra)
        return self.Transaction.create(vals)

    def test_patch43m20_operation_ref_uses_secure_public_reference_format(self):
        tx = self._make_transaction()

        self.assertRegex(tx.operation_ref or '', self.operation_ref_pattern)
        self.assertRegex(tx.name or '', self.name_pattern)
        self.assertNotEqual(tx.name, tx.operation_ref)
        self.assertNotIn(str(tx.id), tx.operation_ref)

    def test_patch43m20_operation_refs_and_names_are_unique_for_generated_rows(self):
        txs = self.Transaction.browse([
            self._make_transaction().id for _idx in range(5)
        ])

        self.assertEqual(len(set(txs.mapped('operation_ref'))), len(txs))
        self.assertEqual(len(set(txs.mapped('name'))), len(txs))
        for tx in txs:
            self.assertRegex(tx.operation_ref or '', self.operation_ref_pattern)
            self.assertRegex(tx.name or '', self.name_pattern)

    def test_patch43m20_manual_public_reference_is_ignored_without_internal_override(self):
        tx = self._make_transaction(
            name='TX/2026/000001',
            operation_ref='TX/2026/000001',
        )

        self.assertNotEqual(tx.name, 'TX/2026/000001')
        self.assertNotEqual(tx.operation_ref, 'TX/2026/000001')
        self.assertRegex(tx.operation_ref or '', self.operation_ref_pattern)
        self.assertRegex(tx.name or '', self.name_pattern)

    def test_patch43m20_collision_precheck_retries_operation_ref_candidate(self):
        existing = self._make_transaction()
        duplicate = existing.operation_ref
        fallback = 'TX-20990101-010101-000000000001'
        calls = {'count': 0}

        def fake_candidate(model):
            calls['count'] += 1
            return duplicate if calls['count'] == 1 else fallback

        with patch.object(type(self.Transaction), '_generate_transaction_reference_candidate', fake_candidate):
            tx = self._make_transaction()

        self.assertEqual(tx.operation_ref, fallback)
        self.assertNotEqual(tx.operation_ref, duplicate)
        self.assertGreaterEqual(calls['count'], 2)

    def test_patch43m20_operation_ref_and_name_are_append_only(self):
        tx = self._make_transaction()

        with self.assertRaises(UserError):
            tx.write({'operation_ref': 'TX-20990101-010101-000000000002'})

        with self.assertRaises(UserError):
            tx.write({'name': 'FTX/2099/000001'})

    def test_patch43m20_internal_log_can_share_operation_ref_for_same_business_operation(self):
        operation_ref = self.Transaction._generate_unique_transaction_reference()

        tx1 = self.Transaction.log(
            'expiration_faces',
            self.env.company,
            operation_ref=operation_ref,
            note='Patch43M20-A shared operation ref 1',
        )
        tx2 = self.Transaction.log(
            'expiration_faces',
            self.env.company,
            operation_ref=operation_ref,
            note='Patch43M20-A shared operation ref 2',
        )

        self.assertEqual(tx1.operation_ref, operation_ref)
        self.assertEqual(tx2.operation_ref, operation_ref)
        self.assertEqual(tx1.operation_ref, tx2.operation_ref)
        self.assertNotEqual(tx1.name, tx2.name)
