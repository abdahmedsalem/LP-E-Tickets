import base64

from odoo.exceptions import ValidationError
from odoo.tests import tagged
from odoo.tests.common import TransactionCase


@tagged('post_install', '-at_install')
class TestPurchaseApiFlow(TransactionCase):
    def setUp(self):
        super().setUp()
        self.purchases = self.env['acpec.fuel.purchase']
        self.partner = self.env['res.partner'].create({'name': 'API flow client'})
        self.carnet_type = self.env['acpec.fuel.carnet.type'].create({
            'face_count': 10, 'face_value': 987123,
            'company_id': self.env.company.id, 'validity_days': 30,
        })

    def _create_purchase(self, **overrides):
        values = {
            'partner': self.partner, 'company': self.env.company,
            'lines': [{'carnet_type_id': self.carnet_type.id, 'carnet_qty': 3}],
            'proof_filename': 'proof.pdf',
            'proof_data': base64.b64encode(b'%PDF-1.4\nproof').decode(),
            'idempotency_key': 'purchase-flow-key', 'request_hash': 'same-request',
        }
        values.update(overrides)
        return self.purchases.create_from_api(**values)

    def test_create_submits_exact_carnet_quantity_with_proof(self):
        purchase = self._create_purchase()
        self.assertEqual(purchase.state, 'submitted')
        self.assertEqual(purchase.line_ids.carnet_qty, 3)
        self.assertEqual(purchase.face_qty_total, 30)
        self.assertEqual(purchase.amount_total, 30 * self.carnet_type.face_value)
        self.assertEqual(len(purchase.proof_attachment_ids), 1)

    def test_retry_returns_same_purchase_without_duplicate_lines_or_proofs(self):
        purchase = self._create_purchase()
        retry = self._create_purchase()
        self.assertEqual(retry, purchase)
        self.assertEqual(len(retry.line_ids), 1)
        self.assertEqual(len(retry.proof_attachment_ids), 1)
        with self.assertRaises(ValidationError), self.cr.savepoint():
            self._create_purchase(request_hash='different-request')

    def test_invalid_lines_leave_no_partial_purchase(self):
        invalid_lines = [
            [], 'invalid', [None],
            [{'carnet_type_id': 'invalid', 'carnet_qty': 3}],
            [{'carnet_type_id': self.carnet_type.id, 'carnet_qty': 'invalid'}],
            [{'carnet_type_id': self.carnet_type.id, 'carnet_qty': 0}],
            [{'carnet_type_id': self.carnet_type.id, 'carnet_qty': -1}],
            [{'carnet_type_id': 0, 'carnet_qty': 1}],
        ]
        count_before = self.purchases.search_count([])
        for lines in invalid_lines:
            with self.subTest(lines=lines):
                with self.assertRaises(ValidationError):
                    self._create_purchase(lines=lines)
                self.assertEqual(self.purchases.search_count([]), count_before)

    def test_inactive_type_is_rejected(self):
        self.carnet_type.active = False
        with self.assertRaises(ValidationError), self.cr.savepoint():
            self._create_purchase()

    def test_type_from_another_company_is_rejected(self):
        other_company = self.env['res.company'].create({'name': 'Other purchase company'})
        other_type = self.env['acpec.fuel.carnet.type'].create({
            'face_count': 10, 'face_value': 987123,
            'company_id': other_company.id, 'validity_days': 30,
        })
        with self.assertRaises(ValidationError), self.cr.savepoint():
            self._create_purchase(lines=[{'carnet_type_id': other_type.id, 'carnet_qty': 1}])
