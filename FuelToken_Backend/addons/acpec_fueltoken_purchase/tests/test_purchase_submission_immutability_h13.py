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
        purchase = self.Purchase.with_context(allow_fuel_purchase_create=True, allow_fuel_purchase_line_create=True).create({
            'partner_id': partner.id,
            'company_id': self.env.company.id,
            'payment_reference': 'PAY-H13-001',
        })
        self.PurchaseLine.with_context(allow_fuel_purchase_line_create=True).create({
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
        purchase.with_context(allow_fuel_purchase_update=True).sudo().write({'proof_attachment_ids': [(4, attachment.id)]})
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
            self.PurchaseLine.with_context(allow_fuel_purchase_line_create=True).create({
                'purchase_id': purchase.id,
                'carnet_type_id': self._carnet_type().id,
                'carnet_qty': 1,
            })

        with self.assertRaises(UserError):
            line.unlink()

    def test_m23a_purchase_view_is_readonly_without_force_save(self):
        form_view = self.env.ref(
            'acpec_fueltoken_purchase.view_fuel_purchase_form'
        )
        form_arch = form_view.arch_db or ''

        self.assertIn(
            '<form create="0" edit="0" delete="0">',
            form_arch,
        )
        self.assertIn(
            'name="state" widget="statusbar" '
            'statusbar_visible="draft,submitted,approved,rejected" '
            'readonly="1"',
            form_arch,
        )
        self.assertIn(
            'name="partner_id" readonly="1"',
            form_arch,
        )
        self.assertIn(
            'name="company_id" readonly="1" '
            'groups="base.group_multi_company"',
            form_arch,
        )
        self.assertIn(
            'name="payment_reference" readonly="1"',
            form_arch,
        )
        self.assertIn(
            'name="proof_attachment_ids" '
            'widget="many2many_binary" readonly="1"',
            form_arch,
        )
        self.assertIn(
            'name="rejection_reason" readonly="1"',
            form_arch,
        )
        self.assertNotIn(
            'force_save=',
            form_arch,
        )

        for button_name in (
            'action_submit',
            'action_approve',
            'action_reject',
        ):
            self.assertIn(
                'name="%s"' % button_name,
                form_arch,
            )

        list_view = self.env.ref(
            'acpec_fueltoken_purchase.view_fuel_purchase_list'
        )
        self.assertIn(
            '<list create="0" edit="0" delete="0">',
            list_view.arch_db or '',
        )

    def test_h13_view_warns_before_approve_or_reject(self):
        view = self.env.ref('acpec_fueltoken_purchase.view_fuel_purchase_form')
        arch = view.arch_db or ''

        self.assertIn('name="action_approve"', arch)
        self.assertIn('confirm="Valider ce lot d\'achat ?', arch)
        self.assertIn('Les lignes, le client, la référence paiement et les preuves resteront verrouillés', arch)

        self.assertIn('name="action_reject"', arch)
        self.assertIn('confirm="Rejeter ce lot d\'achat ?', arch)
        self.assertIn('Le lot restera verrouillé économiquement', arch)

    def test_h13_approval_idempotency_fields_require_model_helper(self):
        purchase = self._submitted_purchase()

        with self.assertRaises(UserError):
            purchase.write({
                'approval_idempotency_key': 'H13-DIRECT',
                'approval_request_hash': 'H13-HASH',
            })

        purchase._set_approval_idempotency('H13-CONTROLLED', 'H13-HASH')
        self.assertEqual(purchase.approval_idempotency_key, 'H13-CONTROLLED')
        self.assertEqual(purchase.approval_request_hash, 'H13-HASH')

        with self.assertRaises(UserError):
            purchase.write({'payment_reference': 'PAY-H13-STILL-BLOCKED'})

    def test_h13_purchase_lines_are_accessed_from_smart_button_grouped_by_carnet_type(self):
        purchase = self._submitted_purchase()
        action = purchase.action_open_purchase_lines()

        self.assertEqual(action['res_model'], 'acpec.fuel.purchase.line')
        self.assertEqual(action['view_mode'], 'list')
        self.assertEqual(action['domain'], [('purchase_id', '=', purchase.id)])
        self.assertEqual(action['context']['default_purchase_id'], purchase.id)
        self.assertEqual(action['context']['group_by'], 'carnet_type_id')

    def test_h13_purchase_form_keeps_only_proofs_and_rejection_pages_for_detail(self):
        view = self.env.ref('acpec_fueltoken_purchase.view_fuel_purchase_form')
        arch = view.arch_db or ''

        self.assertIn('name="action_open_purchase_lines"', arch)
        self.assertIn('name="purchase_line_count" widget="statinfo" string="Détail"', arch)
        self.assertNotIn('string="Lignes de carnets"', arch)
        self.assertNotIn('name="line_ids"', arch)
        self.assertNotIn('string="Technique"', arch)
        self.assertIn('string="Preuves de paiement"', arch)
        self.assertIn('string="Rejet"', arch)

        smart_list = self.env.ref('acpec_fueltoken_purchase.view_fuel_purchase_line_smart_list')
        smart_arch = smart_list.arch_db or ''
        self.assertIn('<list string="Détail du lot achat" create="0" edit="0" delete="0">', smart_arch)

    def test_h13_purchase_line_smart_list_shows_group_totals(self):
        smart_list = self.env.ref('acpec_fueltoken_purchase.view_fuel_purchase_line_smart_list')
        smart_arch = smart_list.arch_db or ''

        self.assertIn('name="carnet_qty" width="90px" sum="Total carnets"', smart_arch)
        self.assertIn('name="generated_face_qty" width="110px" sum="Total tickets"', smart_arch)
        self.assertIn('name="amount_total"', smart_arch)
        self.assertIn('sum="Total montant"', smart_arch)
        self.assertNotIn('name="face_count" sum=', smart_arch)
        self.assertNotIn('name="face_value" sum=', smart_arch)

    def test_h13_purchase_line_smart_list_amount_total_is_monetary_and_summed(self):
        smart_list = self.env.ref('acpec_fueltoken_purchase.view_fuel_purchase_line_smart_list')
        smart_arch = smart_list.arch_db or ''

        self.assertIn('name="currency_id" column_invisible="1"', smart_arch)
        self.assertIn('name="amount_total" width="130px" widget="monetary"', smart_arch)
        self.assertIn('options="{\'currency_field\': \'currency_id\'}"', smart_arch)
        self.assertIn('sum="Total montant"', smart_arch)

    def test_h13_purchase_line_smart_list_has_controlled_column_widths(self):
        smart_list = self.env.ref('acpec_fueltoken_purchase.view_fuel_purchase_line_smart_list')
        smart_arch = smart_list.arch_db or ''

        self.assertIn('name="carnet_type_id" width="260px"', smart_arch)
        self.assertIn('name="carnet_qty" width="90px"', smart_arch)
        self.assertIn('name="face_count" width="100px"', smart_arch)
        self.assertIn('name="face_value" width="120px"', smart_arch)
        self.assertIn('name="generated_face_qty" width="110px"', smart_arch)
        self.assertIn('name="amount_total" width="130px" widget="monetary"', smart_arch)
