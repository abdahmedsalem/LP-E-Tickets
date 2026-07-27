# -*- coding: utf-8 -*-
import inspect

from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_fueltoken_api.controllers.api_common import AcpecFuelTokenApiCommon
from odoo.addons.acpec_fueltoken_api.controllers.api_mobile import AcpecFuelTokenMobileApi
from odoo.addons.acpec_fueltoken_api.controllers.api_station import AcpecFuelTokenStationApi
from odoo.addons.acpec_fueltoken_api.controllers.api_admin import AcpecFuelTokenAdminApi


@tagged("post_install", "-at_install")
class TestSensitiveIdempotencyPolicy(TransactionCase):

    def _source(self, method):
        return inspect.getsource(method)

    def _assert_requires_idempotency(self, method, purpose):
        source = self._source(method)
        self.assertIn("_require_idempotency_key", source)
        self.assertIn("purpose='%s'" % purpose, source)

    def _assert_no_idempotency_requirement(self, method):
        self.assertNotIn("_require_idempotency_key", self._source(method))

    def test_common_helper_exists(self):
        source = self._source(AcpecFuelTokenApiCommon._require_idempotency_key)
        self.assertIn("idempotency_key", source)
        self.assertIn("ValidationError", source)

    def test_mobile_economic_mutations_require_idempotency_key(self):
        for method, purpose in (
            (AcpecFuelTokenMobileApi.create_purchase, "purchase_create"),
            (AcpecFuelTokenMobileApi.issue_qr, "qr_issue"),
            (AcpecFuelTokenMobileApi.retirer_qr, "qr_retirer"),
            (AcpecFuelTokenMobileApi.separer_qr, "qr_separer"),
            (AcpecFuelTokenMobileApi.transfer_carnets, "carnet_transfer"),
        ):
            self._assert_requires_idempotency(method, purpose)

    def test_station_qr_use_requires_idempotency_key(self):
        self._assert_requires_idempotency(AcpecFuelTokenStationApi.use_qr, "station_qr_use")

    def test_read_check_and_admin_list_endpoints_do_not_require_idempotency_key(self):
        for method in (
            AcpecFuelTokenMobileApi.purchases,
            AcpecFuelTokenMobileApi.purchase_detail,
            AcpecFuelTokenMobileApi.qr_list,
            AcpecFuelTokenMobileApi.qr_detail,
            AcpecFuelTokenStationApi.profile,
            AcpecFuelTokenStationApi.check_qr,
            AcpecFuelTokenStationApi.station_transactions,
            AcpecFuelTokenAdminApi.carnet_type_list,
            AcpecFuelTokenAdminApi.purchases_pending,
            AcpecFuelTokenAdminApi.purchase_detail,
            AcpecFuelTokenAdminApi.stations_list,
            AcpecFuelTokenAdminApi.reports_summary,
        ):
            self._assert_no_idempotency_requirement(method)
