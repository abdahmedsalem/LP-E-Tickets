import base64

from odoo.exceptions import UserError
from odoo.tests.common import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestPurchaseSubmissionImmutabilityH13(TransactionCase):

    def setUp(self):
        super().setUp()
        self.Purchase = self.env['acpec.fuel.purchase'].sudo()
        self.PurchaseLine = self.env['acpec.fuel.purchase.line'].sudo()
        self.Partner = self.env['res.partner'].sudo()
        self.Attachment = self.env['ir.attachment'].sudo()
        self.CarnetType = self.env['acpec.fuel.carnet.type'].sudo()

    def _carnet_type(self):
        carnet_type = self.CarnetType.search([('active', '=', True)], limit=1)
        if carnet_type:
            return carnet_type

        vals = {}
        for field_name in ('name', 'code'):
            if field_name in self.CarnetType._fields:
                vals[field_name] = 'H13-C10T-50'
        if 'face_count' in self.CarnetType._fields:
            vals['face_count'] = 10
        if 'face_value' in self.CarnetType._fields:
            vals['face_value'] = 50
        if 'company_id' in self.CarnetType._fields:
            vals['company_id'] = self.env.company.id
        if 'active' in self.CarnetType._fields:
            vals['active'] = True
        return self.CarnetType.create(vals)

    def _submitted_purchase(self):
        partner = self.Partner.create({'name': 'H13 Client'})
        purchase = self.Purchase.create({
            'partner_id': partner.id,
            'company_id': self.env.company.id,
            'payment_reference': 'PAY-H13-001',
        })
        self.PurchaseLine.create({
            'purchase_id': purchase.id,
            'carnet_type_id': self._carnet_type().id,
            'carnet_qty': 1,
        })
        attachment = self.Attachment.create({
            'name': 'preuve-h13.pdf',
            'datas': base64.b64encode(b'%PDF-1.4\n%EOF').decode('ascii'),
            'mimetype': 'application/pdf',
            'res_model': purchase._name,
            'res_id': purchase.id,
            'type': 'binary',
        })
        purchase.write({'proof_attachment_ids': [(4, attachment.id)]})
        purchase.action_submit()
        self.assertEqual(purchase.state, 'submitted')
        return purchase

    def test_h13_submitted_purchase_header_fields_are_immutable(self):
        purchase = self._submitted_purchase()
        other_partner = self.Partner.create({'name': 'H13 Other Client'})

        forbidden_writes = (
            {'partner_id': other_partner.id},
            {'payment_reference': 'PAY-H13-TAMPERED'},
            {'proof_attachment_ids': [(5, 0, 0)]},
            {'line_ids': [(0, 0, {
                'carnet_type_id': self._carnet_type().id,
                'carnet_qty': 1,
            })]},
        )

        for vals in forbidden_writes:
            with self.assertRaises(UserError):
                purchase.write(vals)

    def test_h13_state_cannot_be_tampered_by_direct_write_but_actions_work(self):
        purchase = self._submitted_purchase()

        with self.assertRaises(UserError):
            purchase.write({'state': 'draft'})

        purchase.action_reject()
        self.assertEqual(purchase.state, 'rejected')

    def test_h13_submitted_purchase_lines_are_immutable(self):
        purchase = self._submitted_purchase()
        line = purchase.line_ids[0]

        with self.assertRaises(UserError):
            line.write({'carnet_qty': line.carnet_qty + 1})

        with self.assertRaises(UserError):
            self.PurchaseLine.create({
                'purchase_id': purchase.id,
                'carnet_type_id': self._carnet_type().id,
                'carnet_qty': 1,
            })

        with self.assertRaises(UserError):
            line.unlink()

    def test_h13_view_locks_purchase_after_submission_with_force_save(self):
        view = self.env.ref('acpec_fueltoken_purchase.view_fuel_purchase_form')
        arch = view.arch_db or ''

        self.assertIn('name="partner_id" readonly="state != \'draft\'" force_save="1"', arch)
        self.assertIn('name="payment_reference" readonly="state != \'draft\'" force_save="1"', arch)
        self.assertIn('name="line_ids" readonly="state != \'draft\'" force_save="1"', arch)
        self.assertIn('name="proof_attachment_ids" widget="many2many_binary" readonly="state != \'draft\'" force_save="1"', arch)

    def test_h13_view_warns_before_approve_or_reject(self):
        view = self.env.ref('acpec_fueltoken_purchase.view_fuel_purchase_form')
        arch = view.arch_db or ''

        self.assertIn('name="action_approve"', arch)
        self.assertIn('confirm="Valider ce lot d\'achat ?', arch)
        self.assertIn('Les lignes, le client, la référence paiement et les preuves resteront verrouillés', arch)

        self.assertIn('name="action_reject"', arch)
        self.assertIn('confirm="Rejeter ce lot d\'achat ?', arch)
        self.assertIn('Le lot restera verrouillé économiquement', arch)
