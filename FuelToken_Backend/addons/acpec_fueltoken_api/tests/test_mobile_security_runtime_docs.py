# -*- coding: utf-8 -*-
import inspect

from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_fueltoken_api.controllers.api_admin import AcpecFuelTokenAdminApi


@tagged("post_install", "-at_install")
class TestMobileSecurityRuntimeDocs(TransactionCase):
    # H0C documentation lock: the admin mobile runtime matrix is intentionally
    # restricted to positive validation only.

    def test_h0c_mobile_manager_positive_validator_matrix(self):
        source = inspect.getsource(AcpecFuelTokenAdminApi)
        for purpose in (
            "purchase_approve",
            "device_approve_pending_trust",
        ):
            self.assertIn("purpose='%s'" % purpose, source)

        # H0D: mobile-manager purchase approval is stricter than BO approval.
        # It keeps purchase ownership on partner_id and only adds an API-only
        # guard requiring the partner to have at least one trusted mobile access.
        self.assertIn("_require_purchase_partner_trusted_mobile_access_for_manager_api", source)
        self.assertIn("purchase.with_user(user).action_approve()", source)

        for forbidden in (
            "purpose='purchase_reject'",
            "purpose='station_create'",
            "purpose='station_update'",
            "purpose='station_disable'",
            "purpose='carnet_type_create'",
            "purpose='carnet_type_update'",
            "purpose='carnet_type_delete'",
        ):
            self.assertNotIn(forbidden, source)

        for method_name in (
            "carnet_type_list",
            "carnet_type_create",
            "carnet_type_update",
            "carnet_type_delete",
            "purchase_reject",
            "station_create",
            "station_update",
            "station_disable",
            "reports_summary",
        ):
            method = getattr(AcpecFuelTokenAdminApi, method_name)
            self.assertIn("_raise_mobile_manager_backoffice_only", inspect.getsource(method))
