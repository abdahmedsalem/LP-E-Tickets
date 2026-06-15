from odoo.tests import TransactionCase, tagged

from odoo.addons.acpec_fueltoken_api.controllers.api_common import AcpecFuelTokenApiCommon


@tagged('-at_install', 'post_install')
class TestAcpecFuelTransactionTypeFilter(TransactionCase):

    def setUp(self):
        super().setUp()
        self.controller = AcpecFuelTokenApiCommon()
        self.controller._test_env = self.env

    def test_obsolete_purchase_type_is_rejected_with_replacements(self):
        state, payload = self.controller.classify_transaction_type_filter('achat_carnets')

        self.assertEqual(state, 'obsolete')
        self.assertEqual(payload['transaction_type'], 'achat_carnets')
        self.assertIn('purchase_submitted', payload['replaced_by'])
        self.assertIn('purchase_approved', payload['replaced_by'])
        self.assertIn('achat_carnets', payload['message'])

    def test_known_transaction_type_is_accepted(self):
        state, payload = self.controller.classify_transaction_type_filter('emission_qr')

        self.assertEqual(state, 'ok')
        self.assertEqual(payload, 'emission_qr')

    def test_all_transaction_type_means_no_filter(self):
        state, payload = self.controller.classify_transaction_type_filter('all')

        self.assertEqual(state, 'empty')
        self.assertFalse(payload)

    def test_unknown_transaction_type_is_rejected(self):
        state, payload = self.controller.classify_transaction_type_filter('n_importe_quoi')

        self.assertEqual(state, 'unknown')
        self.assertEqual(payload['transaction_type'], 'n_importe_quoi')
        self.assertIn('emission_qr', payload['allowed_values'])
        self.assertIn('purchase_submitted', payload['allowed_values'])
        self.assertIn('purchase_approved', payload['allowed_values'])
