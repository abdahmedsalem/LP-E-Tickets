# -*- coding: utf-8 -*-
import inspect
import re

from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_fueltoken_api.controllers.api_admin import AcpecFuelTokenAdminApi


@tagged("post_install", "-at_install")
class TestAdminSensitiveInventoryPolicy(TransactionCase):
    # Source-level inventory lock:
    # every admin write endpoint currently classified as sensitive must stay
    # protected by trusted mobile manager + action_code + idempotency/request_hash.
    # Admin read endpoints require trusted manager device, but no action_code/idempotency gate.

    SENSITIVE_ADMIN_WRITE_METHODS = (
        (AcpecFuelTokenAdminApi.purchase_approve, "purchase_approve"),
        (AcpecFuelTokenAdminApi.purchase_reject, "purchase_reject"),
        (AcpecFuelTokenAdminApi.station_create, "station_create"),
        (AcpecFuelTokenAdminApi.station_update, "station_update"),
        (AcpecFuelTokenAdminApi.station_disable, "station_disable"),
        (AcpecFuelTokenAdminApi.carnet_type_create, "carnet_type_create"),
        (AcpecFuelTokenAdminApi.carnet_type_update, "carnet_type_update"),
        (AcpecFuelTokenAdminApi.carnet_type_delete, "carnet_type_delete"),
    )

    ADMIN_READ_METHODS = (
        AcpecFuelTokenAdminApi.carnet_type_list,
        AcpecFuelTokenAdminApi.purchases_pending,
        AcpecFuelTokenAdminApi.purchase_detail,
        AcpecFuelTokenAdminApi.stations_list,
        AcpecFuelTokenAdminApi.reports_summary,
    )

    def _source(self, method):
        return inspect.getsource(method)

    def test_admin_sensitive_write_inventory_is_closed(self):
        expected = {purpose for _method, purpose in self.SENSITIVE_ADMIN_WRITE_METHODS}
        source = inspect.getsource(AcpecFuelTokenAdminApi)
        actual = set(re.findall(r"_trusted_admin_user\(kwargs, purpose='([^']+)'\)", source))
        self.assertEqual(actual, expected)

    def test_admin_sensitive_writes_require_pin_trust_and_idempotency(self):
        for method, purpose in self.SENSITIVE_ADMIN_WRITE_METHODS:
            source = self._source(method)
            self.assertIn("_trusted_admin_user", source)
            self.assertIn("purpose='%s'" % purpose, source)
            self.assertIn("_require_idempotency_key", source)
            self.assertIn("_compute_idempotency_request_hash", source)

    def test_admin_reads_require_trusted_device_but_not_sensitive_or_idempotency_gate(self):
        self.assertIn("_require_trusted_mobile_auth", self._source(AcpecFuelTokenAdminApi._admin_user))
        for method in self.ADMIN_READ_METHODS:
            source = self._source(method)
            self.assertIn("_admin_user", source)
            self.assertNotIn("_trusted_admin_user", source)
            self.assertNotIn("_require_sensitive_action_pin", source)
            self.assertNotIn("_require_idempotency_key", source)
            self.assertNotIn("_compute_idempotency_request_hash", source)
