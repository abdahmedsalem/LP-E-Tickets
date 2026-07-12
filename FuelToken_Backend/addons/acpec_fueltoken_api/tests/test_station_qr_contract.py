# -*- coding: utf-8 -*-
import inspect

from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_fueltoken_api.controllers.api_station import AcpecFuelTokenStationApi
from odoo.addons.acpec_fueltoken_core.models.fuel_qr import AcpecFuelQr


@tagged("post_install", "-at_install")
class TestStationQrContract(TransactionCase):
    """Patch43H2B: station QR contract must remain stable.

    This is intentionally source-level: H2B does not change runtime behavior.
    It prevents future drift between:
    - scan QR graphical code: public_code
    - manual QR numeric code: qr_numeric_code
    - human user code: acpec_human_code, never accepted by station
    """

    def _source(self, method):
        return inspect.getsource(method)

    def test_station_qr_resolver_accepts_only_scan_or_numeric_qr_code(self):
        source = self._source(AcpecFuelTokenStationApi._resolve_qr_from_payload)
        self.assertIn("_resolve_qr_reference_internal", source)
        self.assertIn("public_code=(params or {}).get('public_code')", source)
        self.assertIn("qr_numeric_code=(params or {}).get('qr_numeric_code')", source)
        self.assertNotIn("acpec_human_code", source)

    def test_qr_reference_model_enforces_exactly_one_station_reference(self):
        source = self._source(AcpecFuelQr._resolve_qr_reference_internal)
        self.assertIn("bool(public_code) == bool(qr_numeric_code)", source)
        self.assertIn("Transmettre soit le QR graphique", source)
        self.assertIn("qr_numeric_code_hash", source)
        self.assertNotIn("acpec_human_code", source)

    def test_station_qr_use_is_station_sensitive_action_with_canonical_hash(self):
        source = self._source(AcpecFuelTokenStationApi.use_qr)
        self.assertIn("_sensitive_action_transaction(kwargs, purpose='station_qr_use')", source)
        self.assertIn("_require_fuel_group(user, 'station')", source)
        self.assertIn("_require_idempotency_key(kwargs, purpose='station_qr_use')", source)
        self.assertIn("request_hash_params['public_code'] = qr.public_code", source)
        self.assertIn("request_hash_params.pop('qr_numeric_code', None)", source)
        self.assertIn("_compute_idempotency_request_hash", source)
        self.assertNotIn("acpec_human_code", source)

    def test_station_qr_bearer_semantics_no_owner_device_trust_at_consumption(self):
        combined = "\n".join([
            self._source(AcpecFuelTokenStationApi._resolve_qr_from_payload),
            self._source(AcpecFuelTokenStationApi.check_qr),
            self._source(AcpecFuelTokenStationApi.use_qr),
            self._source(AcpecFuelQr.action_consume_by_station),
        ])

        forbidden_owner_trust_tokens = (
            "qr.partner_id.user_ids",
            "qr.wallet_id.partner_id.user_ids",
            "self.partner_id.user_ids",
            "self.wallet_id.partner_id.user_ids",
            "owner_device",
            "client_device",
            "owner_trust",
            "client_trust",
            "_require_trusted_mobile_auth(owner",
            "_require_trusted_mobile_auth(client",
            "acpec_human_code",
        )
        for token in forbidden_owner_trust_tokens:
            self.assertNotIn(token, combined)

    def test_station_class_does_not_expose_backoffice_management_endpoints(self):
        source = inspect.getsource(AcpecFuelTokenStationApi)
        allowed_routes = (
            "/api/acpec/fueltoken/v1/station/profile",
            "/api/acpec/fueltoken/v1/station/qr/check",
            "/api/acpec/fueltoken/v1/station/qr/use",
            "/api/acpec/fueltoken/v1/station/transactions",
        )
        for route in allowed_routes:
            self.assertIn(route, source)

        forbidden_terms = (
            "purchase_approve",
            "device_approve_pending_trust",
            "carnet_type",
            "station_create",
            "station_write",
            "station_disable",
            "reports_summary",
            "transfer_carnets",
            "issue_qr",
        )
        for term in forbidden_terms:
            self.assertNotIn(term, source)
