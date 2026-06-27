# -*- coding: utf-8 -*-
from pathlib import Path

from odoo.tests.common import TransactionCase, tagged


@tagged("post_install", "-at_install")
class TestMobileSecurityRuntimeDocs(TransactionCase):
    # Documentation lock: the runtime security matrix must mention every sensitive
    # purpose and the key non-negotiable controls. This is intentionally a small
    # source-level guard, not a behavioral runtime test.

    def _doc(self):
        repo_root = Path(__file__).resolve().parents[3]
        doc_path = repo_root / "docs" / "MOBILE_SECURITY_RUNTIME_MATRIX.md"
        self.assertTrue(doc_path.exists(), "%s is missing" % doc_path)
        return doc_path.read_text(encoding="utf-8")

    def test_runtime_matrix_mentions_all_sensitive_purposes(self):
        doc = self._doc()
        for purpose in (
            "purchase_create",
            "qr_issue",
            "qr_retirer",
            "qr_separer",
            "carnet_transfer",
            "station_qr_use",
            "purchase_approve",
            "purchase_reject",
            "station_create",
            "station_update",
            "station_disable",
            "carnet_type_create",
            "carnet_type_update",
            "carnet_type_delete",
        ):
            self.assertIn(purpose, doc)

    def test_runtime_matrix_mentions_non_negotiable_controls(self):
        doc = self._doc()
        for token in (
            "action_code",
            "idempotency_key",
            "request_hash",
            "idempotency_conflict",
            "trusted",
            "secret_code",
            "action_pin",
            "pin",
        ):
            self.assertIn(token, doc)
