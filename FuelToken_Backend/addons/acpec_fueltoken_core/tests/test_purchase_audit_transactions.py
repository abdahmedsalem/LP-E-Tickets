import base64

from odoo.tests import TransactionCase, tagged


@tagged('-at_install', 'post_install')
class TestAcpecFuelPurchaseAuditTransactions(TransactionCase):

    def setUp(self):
        super().setUp()
        self.company = self.env.company
        self.partner = self.env['res.partner'].sudo().create({
            'name': 'Client audit achat',
        })
        self.carnet_type = self._create_unique_carnet_type()
        self.Purchase = self.env['acpec.fuel.purchase'].sudo()
        self.Transaction = self.env['acpec.fuel.transaction'].sudo()
        self.FaceLine = self.env['acpec.fuel.face.line'].sudo()

    def _create_unique_carnet_type(self):
        """Create an isolated carnet type for these tests.

        Some development databases already contain common carnet types such as
        C10T-500. Reusing those values makes the test fragile because the model
        enforces a unique (code, company_id) constraint and code is computed from
        face_count/face_value. Use deliberately high values and check the target
        code before creating the record.
        """
        carnet_model = self.env['acpec.fuel.carnet.type'].sudo()
        face_count = 10
        for face_value in range(900001, 900101):
            code = 'C%sT-%s' % (face_count, face_value)
            if not carnet_model.search([('company_id', '=', self.company.id), ('code', '=', code)], limit=1):
                return carnet_model.create({
                    'face_count': face_count,
                    'face_value': face_value,
                    'validity_days': 365,
                    'company_id': self.company.id,
                })
        self.fail('Impossible de créer un type de carnet isolé pour le test.')

    def _create_purchase(self, carnet_qty=2):
        purchase = self.Purchase.create({
            'partner_id': self.partner.id,
            'company_id': self.company.id,
            'payment_reference': 'PAY-AUDIT-001',
        })
        self.env['acpec.fuel.purchase.line'].sudo().create({
            'purchase_id': purchase.id,
            'carnet_type_id': self.carnet_type.id,
            'carnet_qty': carnet_qty,
        })
        attachment = self.env['ir.attachment'].sudo().create({
            'name': 'preuve.pdf',
            'datas': base64.b64encode(b'%PDF-1.4\npreuve test\n').decode('ascii'),
            'mimetype': 'application/pdf',
            'res_model': purchase._name,
            'res_id': purchase.id,
            'type': 'binary',
        })
        purchase.write({'proof_attachment_ids': [(4, attachment.id)]})
        return purchase

    def _transactions(self, purchase, transaction_type):
        return self.Transaction.search([
            ('purchase_id', '=', purchase.id),
            ('transaction_type', '=', transaction_type),
        ])

    def _all_transactions(self, purchase):
        return self.Transaction.search([
            ('purchase_id', '=', purchase.id),
        ])

    def test_purchase_submit_logs_single_pending_public_transaction_without_fuel_value(self):
        purchase = self._create_purchase(carnet_qty=2)

        purchase.action_submit()

        submitted_txs = self._transactions(purchase, 'purchase_submitted')
        approved_txs = self._transactions(purchase, 'purchase_approved')
        face_lines = self.FaceLine.search([('purchase_id', '=', purchase.id)])

        self.assertEqual(purchase.state, 'submitted')
        self.assertFalse(purchase.fuel_value_created)
        self.assertEqual(len(self._all_transactions(purchase)), 1)
        self.assertEqual(len(submitted_txs), 1)
        self.assertFalse(approved_txs)
        self.assertFalse(face_lines)
        self.assertTrue(submitted_txs.name)
        self.assertTrue(submitted_txs.line_ids)
        self.assertFalse(submitted_txs.line_ids.mapped('face_line_id'))

    def test_purchase_approval_creates_append_only_approved_transaction_once_and_is_idempotent(self):
        """M20-B doctrine: approval creates a second append-only TX row.

        The submitted TX remains immutable. The approved TX materializes the
        real carnets/tickets, receives its own internal name, and reuses the
        same operation_ref for mobile/business grouping.
        """
        purchase = self._create_purchase(carnet_qty=2)

        purchase.action_submit()
        submitted_tx = self._transactions(purchase, 'purchase_submitted')
        self.assertEqual(len(submitted_tx), 1)
        submitted_tx_id = submitted_tx.id
        submitted_tx_name = submitted_tx.name
        submitted_operation_ref = submitted_tx.operation_ref

        purchase.action_approve()
        purchase._create_face_lines_after_approval()

        submitted_txs = self._transactions(purchase, 'purchase_submitted')
        approved_txs = self._transactions(purchase, 'purchase_approved')
        face_lines = self.FaceLine.search([('purchase_id', '=', purchase.id)])

        self.assertEqual(purchase.state, 'approved')
        self.assertTrue(purchase.fuel_value_created)
        self.assertEqual(len(submitted_txs), 1)
        self.assertEqual(len(approved_txs), 1)
        self.assertEqual(len(self._all_transactions(purchase)), 2)
        self.assertEqual(submitted_txs.id, submitted_tx_id)
        self.assertEqual(submitted_txs.name, submitted_tx_name)
        self.assertEqual(submitted_txs.operation_ref, submitted_operation_ref)
        self.assertNotEqual(approved_txs.id, submitted_tx_id)
        self.assertNotEqual(approved_txs.name, submitted_tx_name)
        self.assertEqual(approved_txs.operation_ref, submitted_operation_ref)

        expected_carnet_qty = purchase.line_ids.carnet_qty
        expected_faces_per_carnet = purchase.line_ids.face_count
        expected_qty = purchase.line_ids.generated_face_qty
        expected_amount = purchase.line_ids.amount_total

        self.assertEqual(len(face_lines), expected_carnet_qty)
        self.assertEqual(sum(face_lines.mapped('qty_initial')), expected_qty)
        self.assertEqual(sum(face_lines.mapped('qty_available')), expected_qty)
        self.assertTrue(all(qty == expected_faces_per_carnet for qty in face_lines.mapped('qty_initial')))
        self.assertTrue(all(qty == expected_faces_per_carnet for qty in face_lines.mapped('qty_available')))
        self.assertEqual(len(set(face_lines.mapped('lot_short_code'))), 1)
        self.assertEqual(len(set(face_lines.mapped('carnet_short_code'))), expected_carnet_qty)
        self.assertTrue(all(face_lines.mapped('carnet_no')))

        self.assertTrue(submitted_txs.line_ids)
        self.assertFalse(submitted_txs.line_ids.mapped('face_line_id'))
        self.assertEqual(approved_txs.qty_total, expected_qty)
        self.assertEqual(approved_txs.amount_total, expected_amount)
        self.assertEqual(len(approved_txs.line_ids), expected_carnet_qty)
        self.assertEqual(set(approved_txs.line_ids.mapped('face_line_id').ids), set(face_lines.ids))

        purchase._create_face_lines_after_approval()
        self.assertEqual(len(self._all_transactions(purchase)), 2)
        self.assertEqual(len(self._transactions(purchase, 'purchase_submitted')), 1)
        self.assertEqual(len(self._transactions(purchase, 'purchase_approved')), 1)
        self.assertEqual(len(self.FaceLine.search([('purchase_id', '=', purchase.id)])), expected_carnet_qty)

    def test_purchase_reject_keeps_submitted_transaction_and_creates_no_rejected_tx(self):
        """Rejected purchases do not get a second TX or a purchase_rejected type."""
        purchase = self._create_purchase(carnet_qty=2)

        purchase.action_submit()
        submitted_tx = self._transactions(purchase, 'purchase_submitted')
        self.assertEqual(len(submitted_tx), 1)
        submitted_tx_id = submitted_tx.id
        submitted_tx_name = submitted_tx.name

        purchase.write({'rejection_reason': 'Preuve non conforme'})
        purchase.action_reject()
        purchase.invalidate_recordset(['state', 'rejected_at', 'rejected_by', 'rejection_reason'])
        submitted_tx.invalidate_recordset(['transaction_type', 'purchase_state', 'purchase_rejected_at', 'purchase_rejection_reason'])

        all_txs = self._all_transactions(purchase)
        submitted_txs = self._transactions(purchase, 'purchase_submitted')
        approved_txs = self._transactions(purchase, 'purchase_approved')

        self.assertEqual(purchase.state, 'rejected')
        self.assertEqual(len(all_txs), 1)
        self.assertEqual(len(submitted_txs), 1)
        self.assertFalse(approved_txs)
        self.assertEqual(submitted_txs.id, submitted_tx_id)
        self.assertEqual(submitted_txs.name, submitted_tx_name)
        self.assertEqual(submitted_txs.purchase_state, 'rejected')
        self.assertTrue(submitted_txs.purchase_rejected_at)
        self.assertEqual(submitted_txs.purchase_rejection_reason, 'Preuve non conforme')
