# -*- coding: utf-8 -*-
import inspect

from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_fueltoken_api.controllers.api_admin import AcpecFuelTokenAdminApi
from odoo.addons.acpec_fueltoken_api.controllers.api_mobile import AcpecFuelTokenMobileApi
from odoo.addons.acpec_fueltoken_api.controllers.api_station import AcpecFuelTokenStationApi


@tagged("post_install", "-at_install")
class TestSensitiveActionPinGate(TransactionCase):

    def _source(self, method):
        return inspect.getsource(method)

    def _assert_pin_guard(self, method, purpose):
        source = self._source(method)
        self.assertIn("_sensitive_action_transaction", source)
        self.assertIn("purpose='%s'" % purpose, source)

    def _assert_no_pin_guard(self, method):
        source = self._source(method)
        self.assertNotIn("_require_sensitive_action_pin", source)
        self.assertNotIn("_sensitive_action_transaction", source)

    def test_mobile_sensitive_write_endpoints_require_action_pin(self):
        expectations = (
            (AcpecFuelTokenMobileApi.create_purchase, "purchase_create"),
            (AcpecFuelTokenMobileApi.transfer_carnets, "carnet_transfer"),
            (AcpecFuelTokenMobileApi.issue_qr, "qr_issue"),
            (AcpecFuelTokenMobileApi.retirer_qr, "qr_retirer"),
            (AcpecFuelTokenMobileApi.separer_qr, "qr_separer"),
        )
        for method, purpose in expectations:
            self._assert_pin_guard(method, purpose)

    def test_mobile_read_or_preview_endpoints_require_trust_but_not_action_pin(self):
        self.assertIn("_require_trusted_mobile_auth", self._source(AcpecFuelTokenMobileApi._mobile_wallet))
        for method in (
            AcpecFuelTokenMobileApi.purchases,
            AcpecFuelTokenMobileApi.purchase_detail,
            AcpecFuelTokenMobileApi.transfer_carnets_recipient,
            AcpecFuelTokenMobileApi.transfer_list,
            AcpecFuelTokenMobileApi.qr_list,
            AcpecFuelTokenMobileApi.qr_detail,
        ):
            self._assert_no_pin_guard(method)

    def test_station_sensitive_write_endpoint_requires_action_pin(self):
        source = self._source(AcpecFuelTokenStationApi.use_qr)
        self.assertIn("_sensitive_action_transaction", source)
        self.assertIn("purpose='station_qr_use'", source)

    def test_station_read_or_check_endpoints_require_trust_but_not_action_pin(self):
        self.assertIn("_require_trusted_mobile_auth", self._source(AcpecFuelTokenStationApi._station_user))
        for method in (
            AcpecFuelTokenStationApi.profile,
            AcpecFuelTokenStationApi.check_qr,
            AcpecFuelTokenStationApi.station_transactions,
        ):
            self._assert_no_pin_guard(method)

    def test_admin_sensitive_write_endpoints_require_action_pin(self):
        expectations = (
            (AcpecFuelTokenAdminApi.purchase_approve, "purchase_approve"),
            (AcpecFuelTokenAdminApi.purchase_reject, "purchase_reject"),
            (AcpecFuelTokenAdminApi.station_create, "station_create"),
            (AcpecFuelTokenAdminApi.station_update, "station_update"),
            (AcpecFuelTokenAdminApi.station_disable, "station_disable"),
            (AcpecFuelTokenAdminApi.carnet_type_create, "carnet_type_create"),
            (AcpecFuelTokenAdminApi.carnet_type_update, "carnet_type_update"),
            (AcpecFuelTokenAdminApi.carnet_type_delete, "carnet_type_delete"),
        )
        for method, purpose in expectations:
            source = self._source(method)
            self.assertIn("_sensitive_action_transaction", source)
            self.assertIn("purpose='%s'" % purpose, source)

    def test_admin_read_endpoints_require_trust_but_not_action_pin(self):
        self.assertIn("_require_trusted_mobile_auth", self._source(AcpecFuelTokenAdminApi._admin_user))
        for method in (
            AcpecFuelTokenAdminApi.carnet_type_list,
            AcpecFuelTokenAdminApi.purchases_pending,
            AcpecFuelTokenAdminApi.purchase_detail,
            AcpecFuelTokenAdminApi.stations_list,
            AcpecFuelTokenAdminApi.reports_summary,
        ):
            source = self._source(method)
            self.assertNotIn("_require_sensitive_action_pin", source)
            self.assertNotIn("_sensitive_action_transaction", source)
            self.assertNotIn("_trusted_admin_user(kwargs", source)
