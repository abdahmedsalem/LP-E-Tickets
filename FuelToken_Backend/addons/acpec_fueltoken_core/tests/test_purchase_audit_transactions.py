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

    def test_purchase_submit_logs_submitted_without_fuel_value(self):
        purchase = self._create_purchase(carnet_qty=2)

        purchase.action_submit()

        submitted_txs = self._transactions(purchase, 'purchase_submitted')
        approved_txs = self._transactions(purchase, 'purchase_approved')
        face_lines = self.FaceLine.search([('purchase_id', '=', purchase.id)])

        self.assertEqual(purchase.state, 'submitted')
        self.assertFalse(purchase.fuel_value_created)
        self.assertEqual(len(submitted_txs), 1)
        self.assertFalse(approved_txs)
        self.assertFalse(face_lines)
        self.assertTrue(submitted_txs.line_ids)
        self.assertFalse(submitted_txs.line_ids.mapped('face_line_id'))

    def test_purchase_approval_logs_approved_once_and_is_idempotent(self):
        purchase = self._create_purchase(carnet_qty=2)

        purchase.action_submit()
        purchase.action_approve()
        purchase._create_face_lines_after_approval()

        submitted_txs = self._transactions(purchase, 'purchase_submitted')
        approved_txs = self._transactions(purchase, 'purchase_approved')
        face_lines = self.FaceLine.search([('purchase_id', '=', purchase.id)])

        self.assertEqual(purchase.state, 'approved')
        self.assertTrue(purchase.fuel_value_created)
        self.assertEqual(len(submitted_txs), 1)
        self.assertEqual(len(approved_txs), 1)
        self.assertEqual(len(face_lines), 1)
        expected_qty = purchase.line_ids.generated_face_qty
        expected_amount = purchase.line_ids.amount_total
        self.assertEqual(face_lines.qty_initial, expected_qty)
        self.assertEqual(face_lines.qty_available, expected_qty)
        self.assertEqual(approved_txs.qty_total, expected_qty)
        self.assertEqual(approved_txs.amount_total, expected_amount)
        self.assertEqual(approved_txs.line_ids.face_line_id, face_lines)
