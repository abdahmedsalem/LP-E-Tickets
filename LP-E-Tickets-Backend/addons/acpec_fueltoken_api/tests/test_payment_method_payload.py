from datetime import datetime
from types import SimpleNamespace
from unittest.mock import patch

from odoo.tests import tagged
from odoo.tests.common import TransactionCase

from ..controllers.api_mobile import AcpecFuelTokenMobileApi


@tagged('post_install', '-at_install')
class TestPaymentMethodPayload(TransactionCase):
    def test_catalog_payload_preserves_mobile_contract(self):
        method = SimpleNamespace(
            id=7, code='bankily', name='Bankily', merchant_code='12345',
            image_128='logo', instructions='Instructions', color_hex='#123456',
            sequence=10, company_id=SimpleNamespace(id=3, name='Company'),
        )
        payload = AcpecFuelTokenMobileApi()._mobile_payment_method_payload(method)
        self.assertEqual(payload, {
            'id': 7, 'code': 'bankily', 'name': 'Bankily',
            'display_name': 'Bankily', 'merchant_code': '12345',
            'logo_data': 'logo', 'image_128': 'logo',
            'instructions': 'Instructions', 'color_hex': '#123456',
            'sequence': 10, 'company_id': 3, 'company_name': 'Company',
        })

    def test_purchase_payload_uses_snapshot_instead_of_current_configuration(self):
        purchase = SimpleNamespace(
            payment_method_id=SimpleNamespace(
                id=7, code='changed', name='Changed', merchant_code='67890',
            ),
            payment_method_code='bankily', payment_method_name='Bankily',
            payment_merchant_code='12345',
        )
        payload = AcpecFuelTokenMobileApi()._purchase_payment_method_payload(purchase)
        self.assertEqual(payload, {
            'payment_method_id': 7, 'payment_method_code': 'bankily',
            'payment_method_name': 'Bankily', 'payment_merchant_code': '12345',
        })

    def test_purchase_without_snapshot_does_not_read_current_configuration(self):
        purchase = SimpleNamespace(
            payment_method_id=SimpleNamespace(id=7, name='Current'),
            payment_method_code=False, payment_method_name=False,
            payment_merchant_code=False,
        )
        payload = AcpecFuelTokenMobileApi()._purchase_payment_method_payload(purchase)
        self.assertFalse(payload['payment_method_name'])
        self.assertFalse(payload['payment_merchant_code'])

    def test_purchase_history_uses_frozen_line_size(self):
        controller = AcpecFuelTokenMobileApi()
        purchase = SimpleNamespace(id=12)
        line = SimpleNamespace(
            id=1, carnet_type_id=SimpleNamespace(id=7, code='C10', face_count=99),
            face_count=10, face_value=100, carnet_qty=3,
            generated_face_qty=30, amount_total=3000,
        )
        with patch.object(controller, '_carnet_type_label', return_value='Carnet'):
            payload = controller._purchase_history_line_payload(
                purchase, line, fallback_expiration=datetime(2027, 1, 1),
            )
        self.assertEqual(payload['carnet_size'], 10)
        self.assertEqual(payload['face_count'], 10)
        self.assertEqual(payload['qty'], 30)
        self.assertEqual(payload['amount_total'], 3000)
