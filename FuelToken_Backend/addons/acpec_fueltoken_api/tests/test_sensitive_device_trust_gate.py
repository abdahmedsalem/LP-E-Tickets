# -*- coding: utf-8 -*-
import inspect

from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_fueltoken_api.controllers.api_admin import AcpecFuelTokenAdminApi
from odoo.addons.acpec_fueltoken_api.controllers.api_mobile import AcpecFuelTokenMobileApi


@tagged("post_install", "-at_install")
class TestSensitiveDeviceTrustGate(TransactionCase):

    def _source(self, method):
        return inspect.getsource(method)

    def test_mobile_write_endpoints_require_trusted_device(self):
        self.assertIn(
            "_require_trusted_sensitive",
            self._source(AcpecFuelTokenMobileApi.create_purchase),
        )
        self.assertIn(
            "_require_trusted_sensitive",
            self._source(AcpecFuelTokenMobileApi.transfer_carnets),
        )

    def test_mobile_read_or_preview_endpoints_do_not_require_trusted_device(self):
        self.assertNotIn(
            "_require_trusted_sensitive",
            self._source(AcpecFuelTokenMobileApi.transfer_carnets_recipient),
        )
        self.assertNotIn(
            "_require_trusted_sensitive",
            self._source(AcpecFuelTokenMobileApi.purchases),
        )
        self.assertNotIn(
            "_require_trusted_sensitive",
            self._source(AcpecFuelTokenMobileApi.purchase_detail),
        )

    def test_admin_write_endpoints_require_trusted_manager_device(self):
        self.assertIn(
            "_require_trusted_sensitive",
            self._source(AcpecFuelTokenAdminApi._trusted_admin_user),
        )

        for method in (
            AcpecFuelTokenAdminApi.purchase_approve,
            AcpecFuelTokenAdminApi.purchase_reject,
            AcpecFuelTokenAdminApi.station_create,
            AcpecFuelTokenAdminApi.station_update,
            AcpecFuelTokenAdminApi.station_disable,
        ):
            self.assertIn("_trusted_admin_user", self._source(method))

    def test_admin_read_endpoints_keep_regular_mobile_manager_auth(self):
        for method in (
            AcpecFuelTokenAdminApi.purchases_pending,
            AcpecFuelTokenAdminApi.purchase_detail,
            AcpecFuelTokenAdminApi.stations_list,
            AcpecFuelTokenAdminApi.reports_summary,
        ):
            source = self._source(method)
            self.assertIn("_admin_user", source)
            self.assertNotIn("_trusted_admin_user", source)
