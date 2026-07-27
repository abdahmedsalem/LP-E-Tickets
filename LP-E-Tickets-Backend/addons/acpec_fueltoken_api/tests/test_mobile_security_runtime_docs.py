# -*- coding: utf-8 -*-
import inspect

from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_fueltoken_api.controllers.api_admin import AcpecFuelTokenAdminApi
from odoo.addons.acpec_fueltoken_api.controllers.api_mobile import AcpecFuelTokenMobileApi


@tagged("post_install", "-at_install")
class TestMobileSecurityRuntimeDocs(TransactionCase):
    # Patch43H1 traceability lock.
    # INV-H0C-MANAGER-POSITIVE-VALIDATOR:
    #   admin mobile runtime matrix restricted to positive validation only.
    # INV-H0D-PURCHASE-APPROVAL-PARTNER-TRUSTED-ACCESS:
    #   purchase approval via mobile manager requires trusted access for partner.
    # INV-H0E-CLIENT-WALLET-OPERATIONAL-ROLE-SEGREGATION:
    #   non-empty client wallet is incompatible with station/manager role.

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
        self.assertIn("purchase._approve_internal(user)", source)

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


    def test_h0e_client_wallet_operational_role_segregation_lock(self):
        from odoo.addons.acpec_fueltoken_core.models.fuel_wallet import AcpecFuelWallet
        from odoo.addons.acpec_fueltoken_core.models.fuel_station import AcpecFuelStation
        from odoo.addons.acpec_fueltoken_api.models.mobile_session_device_trust import (
            AcpecMobileDevice,
            AcpecMobileSession,
        )

        wallet_source = inspect.getsource(AcpecFuelWallet)
        station_source = inspect.getsource(AcpecFuelStation)
        device_source = inspect.getsource(AcpecMobileDevice)
        session_source = inspect.getsource(AcpecMobileSession)

        self.assertIn("_fueltoken_partner_has_non_empty_client_wallet", wallet_source)
        self.assertIn("qty_available", wallet_source)
        self.assertIn("qty_qr_active", wallet_source)
        self.assertIn("qty_qr_blocked", wallet_source)
        self.assertIn("_assert_no_non_empty_client_wallet_for_operational_mobile_user", station_source)
        self.assertIn("_assert_users_have_no_non_empty_client_wallet_for_operational_mobile_role", device_source)
        self.assertIn("_assert_users_have_no_non_empty_client_wallet_for_operational_mobile_role", session_source)

    def test_i0_mobile_read_contract_exposes_transferred_out_bucket(self):
        source = inspect.getsource(AcpecFuelTokenMobileApi)
        self.assertIn("qty_transferred_out", source)
        self.assertIn("amount_transferred_out", source)
        self.assertIn("is_transfer_fragment", source)
        self.assertIn("origin_face_line_id", source)
