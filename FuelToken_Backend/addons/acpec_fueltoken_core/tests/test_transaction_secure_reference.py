# -*- coding: utf-8 -*-
import re
from unittest.mock import patch

from odoo.tests.common import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestFuelTransactionSecureReference(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.Transaction = cls.env['acpec.fuel.transaction'].sudo()
        cls.pattern = re.compile(r'^TX-\d{8}-\d{6}-\d{12}$')

    def _make_transaction(self, **extra):
        vals = {
            'transaction_type': 'expiration_faces',
            'company_id': self.env.company.id,
            'note': 'Patch43M11 secure reference fixture',
        }
        vals.update(extra)
        return self.Transaction.create(vals)

    def test_patch43m11_transaction_name_uses_secure_public_reference_format(self):
        tx = self._make_transaction()

        self.assertRegex(tx.name or '', self.pattern)
        self.assertNotRegex(tx.name or '', r'^TX/\d{4}/\d+$')
        self.assertNotIn(str(tx.id), tx.name)

    def test_patch43m11_transaction_names_are_unique_and_non_sequential(self):
        txs = self.Transaction.create([
            {
                'transaction_type': 'expiration_faces',
                'company_id': self.env.company.id,
                'note': 'Patch43M11 batch 1',
            },
            {
                'transaction_type': 'expiration_faces',
                'company_id': self.env.company.id,
                'note': 'Patch43M11 batch 2',
            },
            {
                'transaction_type': 'expiration_faces',
                'company_id': self.env.company.id,
                'note': 'Patch43M11 batch 3',
            },
        ])

        self.assertEqual(len(set(txs.mapped('name'))), len(txs))
        for tx in txs:
            self.assertRegex(tx.name or '', self.pattern)
            self.assertNotRegex(tx.name or '', r'^TX/\d{4}/\d+$')

    def test_patch43m11_manual_name_is_ignored_without_internal_override(self):
        tx = self._make_transaction(name='TX/2026/000001')

        self.assertRegex(tx.name or '', self.pattern)
        self.assertNotEqual(tx.name, 'TX/2026/000001')

    def test_patch43m11_collision_precheck_retries_candidate(self):
        existing = self._make_transaction()
        calls = {'count': 0}
        original = self.Transaction._generate_transaction_reference_candidate

        def fake_candidate(model_self):
            calls['count'] += 1
            if calls['count'] == 1:
                return existing.name
            return original()

        with patch.object(type(self.Transaction), '_generate_transaction_reference_candidate', fake_candidate):
            tx = self._make_transaction()

        self.assertRegex(tx.name or '', self.pattern)
        self.assertNotEqual(tx.name, existing.name)
        self.assertGreaterEqual(calls['count'], 2)
