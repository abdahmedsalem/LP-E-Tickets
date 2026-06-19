# -*- coding: utf-8 -*-
import inspect

from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_fueltoken_api.controllers.api_admin import AcpecFuelTokenAdminApi
from odoo.addons.acpec_fueltoken_api.controllers.api_mobile import AcpecFuelTokenMobileApi


@tagged("post_install", "-at_install")
class TestSensitiveActionPinGate(TransactionCase):

    def _source(self, method):
        return inspect.getsource(method)

    def test_mobile_sensitive_write_endpoints_require_action_pin(self):
        self.assertIn(
            "_require_sensitive_action_pin",
            self._source(AcpecFuelTokenMobileApi.create_purchase),
        )
        self.assertIn(
            "purpose='purchase_create'",
            self._source(AcpecFuelTokenMobileApi.create_purchase),
        )

        self.assertIn(
            "_require_sensitive_action_pin",
            self._source(AcpecFuelTokenMobileApi.transfer_carnets),
        )
        self.assertIn(
            "purpose='carnet_transfer'",
            self._source(AcpecFuelTokenMobileApi.transfer_carnets),
        )

    def test_mobile_read_or_preview_endpoints_do_not_require_action_pin(self):
        for method in (
            AcpecFuelTokenMobileApi.purchases,
            AcpecFuelTokenMobileApi.purchase_detail,
            AcpecFuelTokenMobileApi.transfer_carnets_recipient,
            AcpecFuelTokenMobileApi.transfer_list,
        ):
            self.assertNotIn("_require_sensitive_action_pin", self._source(method))

    def test_admin_sensitive_write_endpoints_require_action_pin(self):
        helper_source = self._source(AcpecFuelTokenAdminApi._trusted_admin_user)
        self.assertIn("_require_sensitive_action_pin", helper_source)

        expectations = (
            (AcpecFuelTokenAdminApi.purchase_approve, "purpose='purchase_approve'"),
            (AcpecFuelTokenAdminApi.purchase_reject, "purpose='purchase_reject'"),
            (AcpecFuelTokenAdminApi.station_create, "purpose='station_create'"),
            (AcpecFuelTokenAdminApi.station_update, "purpose='station_update'"),
            (AcpecFuelTokenAdminApi.station_disable, "purpose='station_disable'"),
        )
        for method, expected in expectations:
            source = self._source(method)
            self.assertIn("_trusted_admin_user", source)
            self.assertIn(expected, source)

    def test_admin_read_endpoints_do_not_require_action_pin(self):
        for method in (
            AcpecFuelTokenAdminApi.purchases_pending,
            AcpecFuelTokenAdminApi.purchase_detail,
            AcpecFuelTokenAdminApi.stations_list,
            AcpecFuelTokenAdminApi.reports_summary,
        ):
            source = self._source(method)
            self.assertNotIn("_require_sensitive_action_pin", source)
            self.assertNotIn("_trusted_admin_user(kwargs", source)
