from odoo.tests.common import TransactionCase


class TestPurchaseFaceLineSmartButtonH13(TransactionCase):

    def test_h13_face_line_smart_button_is_owned_by_core(self):
        view = self.env.ref('acpec_fueltoken_core.view_fuel_purchase_form_face_lines_button_h13')
        self.assertEqual(
            view.inherit_id,
            self.env.ref('acpec_fueltoken_purchase.view_fuel_purchase_form'),
        )
        arch = view.arch_db or ''
        self.assertIn('name="action_open_face_lines"', arch)
        self.assertIn('name="face_line_count" widget="statinfo" string="Carnets"', arch)

    def test_h13_face_line_action_opens_generated_carnets(self):
        partner = self.env['res.partner'].sudo().create({
            'name': 'Client H13 carnets smart button',
        })
        purchase = self.env['acpec.fuel.purchase']._create_internal({
            'partner_id': partner.id,
            'company_id': self.env.company.id,
        })

        action = purchase.action_open_face_lines()

        self.assertEqual(action['res_model'], 'acpec.fuel.face.line')
        self.assertEqual(action['view_mode'], 'list,form')
        self.assertEqual(action['domain'], [('purchase_id', '=', purchase.id)])
        self.assertEqual(action['context']['group_by'], 'carnet_type_id')
