# -*- coding: utf-8 -*-
import inspect

from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_fueltoken_api.controllers.api_admin import AcpecFuelTokenAdminApi
from odoo.addons.acpec_fueltoken_api.controllers.api_mobile import AcpecFuelTokenMobileApi
from odoo.addons.acpec_fueltoken_api.controllers.api_station import AcpecFuelTokenStationApi


@tagged("post_install", "-at_install")
class TestSensitiveDeviceTrustGate(TransactionCase):

    def _source(self, method):
        return inspect.getsource(method)

    def test_mobile_write_endpoints_require_trusted_device_indirectly(self):
        for method in (
            AcpecFuelTokenMobileApi.create_purchase,
            AcpecFuelTokenMobileApi.transfer_carnets,
            AcpecFuelTokenMobileApi.issue_qr,
            AcpecFuelTokenMobileApi.retirer_qr,
            AcpecFuelTokenMobileApi.separer_qr,
        ):
            self.assertIn("_require_sensitive_action_pin", self._source(method))

    def test_mobile_read_or_preview_endpoints_do_not_require_trusted_device(self):
        for method in (
            AcpecFuelTokenMobileApi.transfer_carnets_recipient,
            AcpecFuelTokenMobileApi.purchases,
            AcpecFuelTokenMobileApi.purchase_detail,
            AcpecFuelTokenMobileApi.qr_list,
            AcpecFuelTokenMobileApi.qr_detail,
        ):
            self.assertNotIn("_require_sensitive_action_pin", self._source(method))
            self.assertNotIn("_require_trusted_sensitive", self._source(method))

    def test_station_qr_use_requires_trusted_device_indirectly(self):
        self.assertIn("_require_sensitive_action_pin", self._source(AcpecFuelTokenStationApi._trusted_station_user))
        self.assertIn("_trusted_station_user", self._source(AcpecFuelTokenStationApi.use_qr))

    def test_station_read_or_check_endpoints_keep_regular_station_auth(self):
        for method in (
            AcpecFuelTokenStationApi.profile,
            AcpecFuelTokenStationApi.check_qr,
            AcpecFuelTokenStationApi.station_transactions,
        ):
            source = self._source(method)
            self.assertIn("_station_user", source)
            self.assertNotIn("_trusted_station_user", source)
            self.assertNotIn("_require_sensitive_action_pin", source)

    def test_admin_write_endpoints_require_trusted_manager_device_indirectly(self):
        self.assertIn("_require_sensitive_action_pin", self._source(AcpecFuelTokenAdminApi._trusted_admin_user))

        for method in (
            AcpecFuelTokenAdminApi.purchase_approve,
            AcpecFuelTokenAdminApi.purchase_reject,
            AcpecFuelTokenAdminApi.station_create,
            AcpecFuelTokenAdminApi.station_update,
            AcpecFuelTokenAdminApi.station_disable,
            AcpecFuelTokenAdminApi.carnet_type_create,
            AcpecFuelTokenAdminApi.carnet_type_update,
            AcpecFuelTokenAdminApi.carnet_type_delete,
        ):
            self.assertIn("_trusted_admin_user", self._source(method))

    def test_admin_read_endpoints_keep_regular_mobile_manager_auth(self):
        for method in (
            AcpecFuelTokenAdminApi.carnet_type_list,
            AcpecFuelTokenAdminApi.purchases_pending,
            AcpecFuelTokenAdminApi.purchase_detail,
            AcpecFuelTokenAdminApi.stations_list,
            AcpecFuelTokenAdminApi.reports_summary,
        ):
            source = self._source(method)
            self.assertIn("_admin_user", source)
            self.assertNotIn("_trusted_admin_user", source)
