# -*- coding: utf-8 -*-
import inspect

from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_fueltoken_api.controllers.api_admin import AcpecFuelTokenAdminApi


@tagged("post_install", "-at_install")
class TestAdminManagerApiContract(TransactionCase):
    # INV-H2-MANAGER-MOBILE-API-CONTRACT:
    # manager mobile V1 has a closed positive-validation API contract.

    READ_LIST_METHODS = (
        AcpecFuelTokenAdminApi.purchases_pending,
        AcpecFuelTokenAdminApi.stations_list,
        AcpecFuelTokenAdminApi.devices_pending_trust,
    )

    READ_DETAIL_METHODS = (
        AcpecFuelTokenAdminApi.purchase_detail,
    )

    SENSITIVE_WRITE_METHODS = (
        (AcpecFuelTokenAdminApi.purchase_approve, "purchase_approve"),
        (AcpecFuelTokenAdminApi.device_approve_pending_trust, "device_approve_pending_trust"),
    )

    BACKOFFICE_ONLY_METHODS = (
        AcpecFuelTokenAdminApi.carnet_type_list,
        AcpecFuelTokenAdminApi.carnet_type_create,
        AcpecFuelTokenAdminApi.carnet_type_update,
        AcpecFuelTokenAdminApi.carnet_type_delete,
        AcpecFuelTokenAdminApi.purchase_reject,
        AcpecFuelTokenAdminApi.station_create,
        AcpecFuelTokenAdminApi.station_update,
        AcpecFuelTokenAdminApi.station_disable,
        AcpecFuelTokenAdminApi.reports_summary,
    )

    def _source(self, method):
        return inspect.getsource(method)

    def test_h2_mobile_manager_allowed_surface_is_explicit(self):
        allowed = {
            method.__name__
            for method in self.READ_LIST_METHODS + self.READ_DETAIL_METHODS
        }
        allowed.update(method.__name__ for method, _purpose in self.SENSITIVE_WRITE_METHODS)
        self.assertEqual(allowed, {
            "purchases_pending",
            "purchase_detail",
            "purchase_approve",
            "stations_list",
            "devices_pending_trust",
            "device_approve_pending_trust",
        })

    def test_h2_read_endpoints_require_manager_trusted_device_without_action_pin(self):
        self.assertIn("_require_trusted_mobile_auth", self._source(AcpecFuelTokenAdminApi._admin_user))
        for method in self.READ_LIST_METHODS + self.READ_DETAIL_METHODS:
            source = self._source(method)
            self.assertIn("_admin_user()", source)
            if method == AcpecFuelTokenAdminApi.purchase_detail:
                self.assertIn("_check_record_company_allowed(user, purchase)", source)
            else:
                self.assertIn("_company_domain_for_user(user)", source)
            self.assertIn("_json_response", source)
            self.assertNotIn("_sensitive_action_transaction", source)
            self.assertNotIn("_require_sensitive_action_pin", source)
            self.assertNotIn("_require_idempotency_key", source)

    def test_h2_paginated_read_lists_keep_opt_in_pagination_contract(self):
        for method in (
            AcpecFuelTokenAdminApi.purchases_pending,
            AcpecFuelTokenAdminApi.devices_pending_trust,
        ):
            source = self._source(method)
            self.assertIn("_pagination_params(kwargs, default_limit=100, max_limit=200)", source)
            self.assertIn("_include_pagination_meta(kwargs)", source)
            self.assertIn("_pagination_meta_count_only(total, limit, offset, len(records), include_meta)", source)
            self.assertIn("search_count(domain)", source)
            self.assertIn("limit=limit", source)
            self.assertIn("offset=offset", source)

    def test_h2_station_list_keeps_small_reference_list_contract(self):
        source = self._source(AcpecFuelTokenAdminApi.stations_list)
        self.assertIn("_admin_user()", source)
        self.assertIn("_company_domain_for_user(user)", source)
        self.assertIn("_station_payload(station)", source)
        self.assertIn("'items'", source)
        self.assertIn("'count': len(records)", source)
        self.assertNotIn("_pagination_params", source)
        self.assertNotIn("_require_idempotency_key", source)
        self.assertNotIn("_sensitive_action_transaction", source)

    def test_h2_purchase_detail_keeps_detail_payload_and_company_scope(self):
        source = self._source(AcpecFuelTokenAdminApi.purchase_detail)
        self.assertIn("_require_keys(kwargs, ['purchase_id'])", source)
        self.assertIn("_check_record_company_allowed(user, purchase)", source)
        self.assertIn("_purchase_payload(purchase, detail=True)", source)

    def test_h2_sensitive_writes_require_pin_idempotency_hash_and_company_scope(self):
        for method, purpose in self.SENSITIVE_WRITE_METHODS:
            source = self._source(method)
            self.assertIn("_sensitive_action_transaction(kwargs, purpose='%s')" % purpose, source)
            self.assertIn("_require_fuel_group(user, 'manager')", source)
            self.assertIn("_require_idempotency_key(kwargs, purpose='%s')" % purpose, source)
            self.assertIn("_compute_idempotency_request_hash(kwargs, purpose='%s')" % purpose, source)
            self.assertIn("_check_record_company_allowed(user,", source)
            self.assertIn("_json_response", source)

    def test_h2_purchase_approve_keeps_h0d_partner_trusted_access_and_replay_contract(self):
        source = self._source(AcpecFuelTokenAdminApi.purchase_approve)
        self.assertIn("purchase.approval_idempotency_key == idempotency_key", source)
        self.assertIn("purchase.approval_request_hash and purchase.approval_request_hash != request_hash", source)
        self.assertIn("purchase.state == 'approved'", source)
        self.assertIn("_require_purchase_partner_trusted_mobile_access_for_manager_api(purchase)", source)
        self.assertIn("purchase.with_user(user).action_approve()", source)

    def test_h2_device_approve_keeps_positive_validator_and_audit_context_contract(self):
        source = self._source(AcpecFuelTokenAdminApi.device_approve_pending_trust)
        self.assertIn("device.user_id == user", source)
        self.assertIn("not device.user_id.acpec_mobile_only", source)
        self.assertIn("device.user_id.acpec_mobile_state == 'blocked'", source)
        self.assertIn("device.trust_state != 'pending_trust'", source)
        self.assertIn("acpec_mobile_source_session_id", source)
        self.assertIn("acpec_fueltoken_mobile_manager_device_approval_user_id", source)
        self.assertIn("acpec_fueltoken_device_approval_idempotency_key", source)
        self.assertIn("acpec_fueltoken_device_approval_request_hash", source)
        self.assertIn("action_trust_device()", source)
        self.assertIn("_device_payload(device)", source)

    def test_h2_backoffice_only_endpoints_remain_fail_closed(self):
        for method in self.BACKOFFICE_ONLY_METHODS:
            source = self._source(method)
            self.assertIn("_admin_user()", source)
            self.assertIn("_raise_mobile_manager_backoffice_only", source)
            self.assertNotIn("_sensitive_action_transaction", source)
            self.assertNotIn("_require_idempotency_key", source)
