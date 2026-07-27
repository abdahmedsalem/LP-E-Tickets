import inspect

from odoo.tests.common import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestBoLineDisplayNameH12(TransactionCase):

    def test_h12_face_line_uses_carnet_short_code_as_rec_name(self):
        model = self.env['acpec.fuel.face.line']
        self.assertEqual(model._rec_name, 'carnet_short_code')
        self.assertIn('carnet_short_code', model._fields)

    def test_h12_purchase_line_has_computed_name_rec_name_without_qty_suffix(self):
        model = self.env['acpec.fuel.purchase.line']
        self.assertEqual(model._rec_name, 'name')
        self.assertIn('name', model._fields)

        field = model._fields['name']
        self.assertEqual(field.compute, '_compute_name')
        self.assertTrue(field.store)
        self.assertTrue(field.readonly)

        cls = type(model)
        source = inspect.getsource(cls._compute_name)
        self.assertIn('purchase_id.name', source)
        self.assertIn('C%sT-%s%s', source)
        self.assertIn('rec.name', source)
        self.assertNotIn('x%s', source)
        self.assertNotIn('carnet_qty or 0', source)

    def test_h12_qr_line_qty_label_is_tickets(self):
        model = self.env['acpec.fuel.qr.line']
        self.assertIn('qty', model._fields)
        self.assertEqual(model._fields['qty'].string, 'Tickets')

    def test_h12_public_code_is_not_exposed_in_backoffice_views(self):
        views = self.env['ir.ui.view'].search([
            ('model', 'in', ['acpec.fuel.qr', 'acpec.fuel.qr.line', 'acpec.fuel.purchase', 'acpec.fuel.carnet.transfer']),
        ])
        self.assertTrue(views)

        for view in views:
            arch = view.arch_db or ''
            self.assertNotIn('name="public_code"', arch, view.name)
            self.assertNotIn("name='public_code'", arch, view.name)
            self.assertNotIn('Code public', arch, view.name)
