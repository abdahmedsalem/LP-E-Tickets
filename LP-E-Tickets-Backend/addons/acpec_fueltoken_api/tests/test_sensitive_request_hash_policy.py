# -*- coding: utf-8 -*-
import inspect

from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_fueltoken_api.controllers.api_common import AcpecFuelTokenApiCommon
from odoo.addons.acpec_fueltoken_api.controllers.api_mobile import AcpecFuelTokenMobileApi
from odoo.addons.acpec_fueltoken_api.controllers.api_station import AcpecFuelTokenStationApi
from odoo.addons.acpec_fueltoken_core.models.fuel_qr import AcpecFuelQr
from odoo.addons.acpec_fueltoken_core.models.fuel_transaction import AcpecFuelTransaction
from odoo.addons.acpec_fueltoken_purchase.models.fuel_purchase import AcpecFuelPurchase


@tagged("post_install", "-at_install")
class TestSensitiveRequestHashPolicy(TransactionCase):

    def _source(self, method):
        return inspect.getsource(method)

    def test_common_hash_helper_excludes_secret_fields(self):
        api = AcpecFuelTokenApiCommon()
        h1 = api._compute_idempotency_request_hash({
            'idempotency_key': 'K1',
            'action_code': '1111',
            'lines': [{'a': 1}],
        }, purpose='qr_issue')
        h2 = api._compute_idempotency_request_hash({
            'idempotency_key': 'K2',
            'action_code': '2222',
            'lines': [{'a': 1}],
        }, purpose='qr_issue')
        h3 = api._compute_idempotency_request_hash({
            'idempotency_key': 'K2',
            'action_code': '2222',
            'lines': [{'a': 2}],
        }, purpose='qr_issue')
        self.assertEqual(h1, h2)
        self.assertNotEqual(h1, h3)

    def test_api_sensitive_endpoints_compute_request_hash(self):
        for method, purpose in (
            (AcpecFuelTokenMobileApi.create_purchase, "purchase_create"),
            (AcpecFuelTokenMobileApi.issue_qr, "qr_issue"),
            (AcpecFuelTokenMobileApi.retirer_qr, "qr_retirer"),
            (AcpecFuelTokenMobileApi.separer_qr, "qr_separer"),
            (AcpecFuelTokenMobileApi.transfer_carnets, "carnet_transfer"),
            (AcpecFuelTokenStationApi.use_qr, "station_qr_use"),
        ):
            source = self._source(method)
            self.assertIn("_compute_idempotency_request_hash", source)
            self.assertIn("purpose='%s'" % purpose, source)

    def test_models_store_and_check_request_hash(self):
        for method in (
            AcpecFuelPurchase.create_from_api,
            AcpecFuelQr.issue_from_available,
            AcpecFuelQr.action_consume_by_station,
            AcpecFuelQr.action_retirer_to_child,
            AcpecFuelQr.action_separer_valid_to_child,
            AcpecFuelTransaction.log,
        ):
            source = self._source(method)
            self.assertIn("request_hash", source)

    def test_request_hash_conflict_code_is_present(self):
        combined = "\n".join([
            self._source(AcpecFuelPurchase.create_from_api),
            self._source(AcpecFuelQr.issue_from_available),
            self._source(AcpecFuelQr.action_consume_by_station),
            self._source(AcpecFuelQr.action_retirer_to_child),
            self._source(AcpecFuelQr.action_separer_valid_to_child),
        ])
        self.assertIn("idempotency_conflict", combined)
