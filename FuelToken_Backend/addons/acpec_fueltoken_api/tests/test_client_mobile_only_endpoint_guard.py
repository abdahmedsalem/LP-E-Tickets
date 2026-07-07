# -*- coding: utf-8 -*-
import pathlib

from odoo.tests.common import TransactionCase, tagged


@tagged("post_install", "-at_install", "patch2s_backend_guard")
class TestClientMobileOnlyEndpointGuard(TransactionCase):
    """Patch2S-B: client mobile-only endpoints keep client role guard."""

    def _source(self):
        root = pathlib.Path(__file__).resolve().parents[1]
        return (root / "controllers" / "api_mobile.py").read_text(encoding="utf-8")

    def _block(self, source, start, end):
        i = source.index(start)
        j = source.index(end, i)
        return source[i:j]

    def test_purchase_create_uses_mobile_wallet_client_guard(self):
        source = self._source()
        block = self._block(
            source,
            "def create_purchase(self, **kwargs):",
            "@http.route('/api/acpec/fueltoken/v1/mobile/purchases'",
        )
        self.assertIn("wallet = self._mobile_wallet()", block)

    def test_qr_issue_uses_mobile_wallet_client_guard(self):
        source = self._source()
        block = self._block(
            source,
            "def issue_qr(self, **kwargs):",
            "@http.route('/api/acpec/fueltoken/v1/mobile/qr/list'",
        )
        self.assertIn("wallet = self._mobile_wallet()", block)

    def test_ticket_transfer_uses_client_role_guard(self):
        source = self._source()
        block = self._block(
            source,
            "def transfer_tickets(self, **kwargs):",
            "@http.route(\n        '/api/acpec/fueltoken/v1/mobile/carnets/transfer/recipient'",
        )
        self.assertIn("self._require_fuel_group(source_user, 'client')", block)

    def test_carnet_transfer_recipient_uses_client_role_guard(self):
        source = self._source()
        block = self._block(
            source,
            "def transfer_carnets_recipient(self, **kwargs):",
            "@http.route(\n        '/api/acpec/fueltoken/v1/mobile/carnets/transfer'",
        )
        self.assertIn("self._require_fuel_group(source_user, 'client')", block)

    def test_carnet_transfer_uses_client_role_guard(self):
        source = self._source()
        block = self._block(
            source,
            "def transfer_carnets(self, **kwargs):",
            "@http.route(\n        '/api/acpec/fueltoken/v1/mobile/carnets/transfers'",
        )
        self.assertIn("self._require_fuel_group(source_user, 'client')", block)
