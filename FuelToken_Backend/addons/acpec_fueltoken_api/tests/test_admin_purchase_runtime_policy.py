# -*- coding: utf-8 -*-
import base64
from types import SimpleNamespace
from unittest.mock import patch


def _acpec_test_mobile_phone(label):
    """Return a deterministic canonical 8-digit mobile phone for test labels."""
    value = 2166136261
    for char in str(label):
        value ^= ord(char)
        value = (value * 16777619) % 10000000
    return "3%07d" % value

from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_fueltoken_api.controllers import api_admin as api_admin_module
from odoo.addons.acpec_fueltoken_api.controllers.api_admin import AcpecFuelTokenAdminApi


@tagged("post_install", "-at_install")
class TestAdminPurchaseRuntimePolicy(TransactionCase):
    # Runtime policy coverage for admin purchase approve/reject.
    # These admin economic decisions require trusted manager device,
    # action_code, idempotency_key and request_hash conflict protection.

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.company = cls.env.company

    def _create_unique_carnet_type(self):
        carnet_model = self.env["acpec.fuel.carnet.type"].sudo()
        face_count = 10
        for face_value in range(960001, 960701):
            code = "C%sT-%s" % (face_count, face_value)
            if not carnet_model.search([
                ("company_id", "=", self.company.id),
                ("code", "=", code),
            ], limit=1):
                return carnet_model.create({
                    "face_count": face_count,
                    "face_value": face_value,
                    "validity_days": 365,
                    "company_id": self.company.id,
                })
        self.fail("Impossible de créer un type de carnet isolé pour le test admin achat.")

    def _group_ids(self, xmlids):
        ids = []
        for xmlid in xmlids:
            group = self.env.ref(xmlid, raise_if_not_found=False)
            if group:
                ids.append(group.id)
        return ids

    def _manager_group_ids(self):
        return self._group_ids([
            "base.group_portal",
            "acpec_mobile_auth.group_mobile_auth_user",
            "acpec_fueltoken_base.group_fuel_manager",
        ])

    def _create_manager_user(self, login):
        user_model = self.env["res.users"].sudo().with_context(
            acpec_mobile_allow_password_write=True,
            no_reset_password=True,
        )
        user = user_model.create({
            "name": login,
            "login": _acpec_test_mobile_phone(login),
            "mobile_phone": _acpec_test_mobile_phone(login),
            "email": login,
            "active": True,
            "company_id": self.company.id,
            "company_ids": [(6, 0, [self.company.id])],
            "mobile_only": True,
            "mobile_state": "approved",
            "password": user_model._acpec_mobile_unusable_password(),
            "group_ids": [(6, 0, self._manager_group_ids())],
        })
        user.set_mobile_pin("1234")
        return user

    def _client_group_ids(self):
        return self._group_ids([
            "base.group_portal",
            "acpec_mobile_auth.group_mobile_auth_user",
            "acpec_fueltoken_base.group_fuel_user",
        ])

    def _create_client_mobile_user(self, suffix, trust_state="trusted"):
        user_model = self.env["res.users"].sudo().with_context(
            acpec_mobile_allow_password_write=True,
            no_reset_password=True,
        )
        login = "client-%s@example.com" % suffix
        user = user_model.create({
            "name": login,
            "login": _acpec_test_mobile_phone(login),
            "mobile_phone": _acpec_test_mobile_phone(login),
            "email": login,
            "active": True,
            "company_id": self.company.id,
            "company_ids": [(6, 0, [self.company.id])],
            "mobile_only": True,
            "mobile_state": "approved",
            "password": user_model._acpec_mobile_unusable_password(),
            "group_ids": [(6, 0, self._client_group_ids())],
        })
        if user.partner_id:
            user.partner_id.sudo().write({
                "company_id": self.company.id,
            })

        token_data = self.env["acpec.mobile.session"].sudo().create_for_user(user, {
            "device_uid": "dev-client-%s" % str(suffix).replace("@", "-").replace(".", "-").replace(" ", "-"),
            "platform": "android",
        })
        session = token_data["session"]

        if trust_state == "trusted":
            session.action_trust_device()
        elif trust_state == "blocked":
            session.device_id.action_block_device(reason="H0D client device blocked fixture")
        elif trust_state in ("pending_trust", "pending", False, None):
            pass
        else:
            raise AssertionError("Unknown client trust_state fixture: %s" % trust_state)

        return user, session

    def _admin_controller(self, login, trusted=True):
        manager = self._create_manager_user(login)
        token_data = self.env["acpec.mobile.session"].sudo().create_for_user(manager, {
            "device_uid": "dev-admin-%s" % login.replace("@", "-").replace(".", "-"),
            "platform": "android",
        })
        session = token_data["session"]
        if trusted:
            session.action_trust_device()

        controller = AcpecFuelTokenAdminApi()
        controller._test_env = self.env
        controller._get_mobile_session = lambda required=True: session
        return controller, manager, session

    def _create_submitted_purchase(self, suffix, partner_mobile_access="trusted"):
        carnet_type = self._create_unique_carnet_type()
        if partner_mobile_access:
            client_user, _client_session = self._create_client_mobile_user(
                suffix,
                trust_state=partner_mobile_access,
            )
            partner = client_user.partner_id.sudo()
        else:
            partner = self.env["res.partner"].sudo().create({
                "name": "Client admin purchase %s" % suffix,
                "company_id": self.company.id,
            })
        purchase = self.env["acpec.fuel.purchase"].sudo().create({
            "partner_id": partner.id,
            "company_id": self.company.id,
            "payment_reference": "PAY-ADMIN-PURCHASE-%s" % suffix,
        })
        self.env["acpec.fuel.purchase.line"].sudo().create({
            "purchase_id": purchase.id,
            "carnet_type_id": carnet_type.id,
            "carnet_qty": 1,
        })
        attachment = self.env["ir.attachment"].sudo().create({
            "name": "preuve.pdf",
            "datas": base64.b64encode(b"%PDF-1.4\npreuve admin purchase 25A\n").decode("ascii"),
            "mimetype": "application/pdf",
            "res_model": purchase._name,
            "res_id": purchase.id,
            "type": "binary",
        })
        purchase.write({"proof_attachment_ids": [(4, attachment.id)]})
        purchase.action_submit()
        purchase.invalidate_recordset(["state"])
        self.assertEqual(purchase.state, "submitted")
        return carnet_type, partner, purchase

    def _call_approve(self, controller, payload):
        fake_request = SimpleNamespace(env=self.env)
        with patch.object(api_admin_module, "request", fake_request):
            return controller.purchase_approve(**payload)

    def _call_reject(self, controller, payload):
        fake_request = SimpleNamespace(env=self.env)
        with patch.object(api_admin_module, "request", fake_request):
            return controller.purchase_reject(**payload)

    def _assert_error_contains(self, response, expected):
        self.assertIn("success", repr(response))
        self.assertIn("False", repr(response))

        error = response.get("error", {}) if isinstance(response, dict) else {}
        code = error.get("code")
        public_message = error.get("message") or ""

        sensitive_expected_codes = {
            "action_code": ("ACTION_REFUSED", "MISSING_ACTION_CODE", "INVALID_ACTION_CODE_KEY"),
            "Device mobile en attente de validation": ("DEVICE_NOT_ALLOWED", "DEVICE_PENDING_TRUST"),
            "PIN mobile invalide": ("ACTION_REFUSED", "INVALID_ACTION_CODE"),
            "Clé PIN action invalide": ("ACTION_REFUSED", "INVALID_ACTION_CODE_KEY"),
            "idempotency_conflict": ("REQUEST_REFUSED",),
            "QR introuvable": ("QR_NOT_USABLE",),
        }
        sensitive_expected_public_messages = {
            "idempotency_conflict": "Cette demande ne peut pas être traitée.",
            "QR introuvable": "QR introuvable ou non utilisable.",
        }

        if expected in sensitive_expected_codes:
            self.assertIn(code, sensitive_expected_codes[expected])
            self.assertTrue(str(error.get("reference") or "").startswith("SEC-"))
            if expected in sensitive_expected_public_messages:
                self.assertEqual(public_message, sensitive_expected_public_messages[expected])
            else:
                self.assertNotIn(expected, public_message)
            return

        self.assertIn(expected, repr(response))

    def _approve_payload(self, purchase, key="admin-approve-runtime-key", **extra):
        payload = {
            "purchase_id": purchase.id,
            "action_code": "1234",
            "idempotency_key": key,
        }
        payload.update(extra)
        return payload

    def _reject_payload(self, purchase, key="admin-reject-runtime-key", **extra):
        payload = {
            "purchase_id": purchase.id,
            "action_code": "1234",
            "idempotency_key": key,
            "rejection_reason": "Rejet runtime 25A",
        }
        payload.update(extra)
        return payload

    def _face_lines_for_purchase(self, purchase):
        return self.env["acpec.fuel.face.line"].sudo().search([
            ("purchase_id", "=", purchase.id),
        ])

    def _approved_txs_for_purchase(self, purchase):
        return self.env["acpec.fuel.transaction"].sudo().search([
            ("transaction_type", "=", "purchase_approved"),
            ("purchase_id", "=", purchase.id),
        ])

    def test_purchase_approve_requires_action_code_only(self):
        controller, _manager, _session = self._admin_controller("admin-approve-action-code-25a@example.com")
        _carnet_type, _partner, purchase = self._create_submitted_purchase("approve-action-code")

        missing = self._approve_payload(purchase, key="approve-missing-action-code-25a")
        missing.pop("action_code")
        self._assert_error_contains(
            self._call_approve(controller, missing),
            "action_code",
        )
        purchase.invalidate_recordset(["state"])
        self.assertEqual(purchase.state, "submitted")
        self.assertFalse(self._face_lines_for_purchase(purchase))

        for alias in ("action_pin", "pin", "secret_code"):
            payload = self._approve_payload(purchase, key="approve-alias-%s-25a" % alias)
            payload.pop("action_code")
            payload[alias] = "1234"
            self._assert_error_contains(
                self._call_approve(controller, payload),
                "action_code",
            )
            purchase.invalidate_recordset(["state"])
            self.assertEqual(purchase.state, "submitted")
            self.assertFalse(self._face_lines_for_purchase(purchase))

    def test_purchase_approve_requires_idempotency_key(self):
        controller, _manager, _session = self._admin_controller("admin-approve-idem-25a@example.com")
        _carnet_type, _partner, purchase = self._create_submitted_purchase("approve-idem-required")

        payload = self._approve_payload(purchase, key="approve-will-be-removed-25a")
        payload.pop("idempotency_key")
        self._assert_error_contains(
            self._call_approve(controller, payload),
            "idempotency_key",
        )
        purchase.invalidate_recordset(["state"])
        self.assertEqual(purchase.state, "submitted")
        self.assertFalse(self._face_lines_for_purchase(purchase))

    def test_purchase_approve_requires_trusted_manager_device(self):
        controller, _manager, _session = self._admin_controller(
            "admin-approve-untrusted-25a@example.com",
            trusted=False,
        )
        _carnet_type, _partner, purchase = self._create_submitted_purchase("approve-untrusted")

        response = self._call_approve(
            controller,
            self._approve_payload(purchase, key="approve-untrusted-25a"),
        )
        self._assert_error_contains(response, "Device mobile en attente de validation")
        purchase.invalidate_recordset(["state"])
        self.assertEqual(purchase.state, "submitted")
        self.assertFalse(self._face_lines_for_purchase(purchase))

    def test_purchase_approve_requires_partner_trusted_mobile_access(self):
        controller, _manager, _session = self._admin_controller("admin-approve-partner-no-mobile-h0d@example.com")
        _carnet_type, _partner, purchase = self._create_submitted_purchase(
            "approve-partner-no-mobile-h0d",
            partner_mobile_access=False,
        )

        response = self._call_approve(
            controller,
            self._approve_payload(purchase, key="approve-partner-no-mobile-h0d"),
        )
        self._assert_error_contains(response, "accès mobile trusted")
        purchase.invalidate_recordset(["state", "approved_by"])
        self.assertEqual(purchase.state, "submitted")
        self.assertFalse(purchase.approved_by)
        self.assertFalse(self._face_lines_for_purchase(purchase))
        self.assertFalse(self._approved_txs_for_purchase(purchase))

    def test_purchase_approve_requires_partner_device_trusted_not_pending_or_blocked(self):
        controller, _manager, _session = self._admin_controller("admin-approve-partner-device-h0d@example.com")

        for trust_state in ("pending_trust", "blocked"):
            _carnet_type, _partner, purchase = self._create_submitted_purchase(
                "approve-partner-%s-h0d" % trust_state,
                partner_mobile_access=trust_state,
            )
            response = self._call_approve(
                controller,
                self._approve_payload(
                    purchase,
                    key="approve-partner-%s-h0d" % trust_state,
                ),
            )
            self._assert_error_contains(response, "accès mobile trusted")
            purchase.invalidate_recordset(["state", "approved_by"])
            self.assertEqual(purchase.state, "submitted")
            self.assertFalse(purchase.approved_by)
            self.assertFalse(self._face_lines_for_purchase(purchase))
            self.assertFalse(self._approved_txs_for_purchase(purchase))

    def test_purchase_approve_replays_same_payload_for_same_idempotency_key(self):
        controller, manager, _session = self._admin_controller("admin-approve-replay-25a@example.com")
        carnet_type, partner, purchase = self._create_submitted_purchase("approve-replay")
        key = "approve-replay-key-25a"
        payload = self._approve_payload(purchase, key=key)

        first_response = self._call_approve(controller, dict(payload))
        second_response = self._call_approve(controller, dict(payload))
        self.assertIn("approved", repr(first_response))
        self.assertIn("approved", repr(second_response))

        purchase.invalidate_recordset([
            "state", "approved_by", "approval_idempotency_key", "approval_request_hash",
        ])
        self.assertEqual(purchase.state, "approved")
        self.assertEqual(purchase.approved_by.id, manager.id)
        self.assertEqual(purchase.approval_idempotency_key, key)
        self.assertTrue(purchase.approval_request_hash)

        face_lines = self._face_lines_for_purchase(purchase)
        self.assertEqual(len(face_lines), 1)
        self.assertEqual(face_lines.partner_id.id, partner.id)
        self.assertEqual(face_lines.qty_initial, carnet_type.face_count)
        self.assertEqual(face_lines.qty_available, carnet_type.face_count)

        approved_txs = self._approved_txs_for_purchase(purchase)
        self.assertEqual(len(approved_txs), 1)
        self.assertEqual(approved_txs.idempotency_key, key)
        self.assertEqual(approved_txs.request_hash, purchase.approval_request_hash)

    def test_purchase_approve_rejects_same_key_with_different_payload(self):
        controller, _manager, _session = self._admin_controller("admin-approve-conflict-25a@example.com")
        _carnet_type, _partner, purchase = self._create_submitted_purchase("approve-conflict")
        key = "approve-conflict-key-25a"

        first = self._call_approve(
            controller,
            self._approve_payload(purchase, key=key, client_nonce="A"),
        )
        self.assertNotIn("idempotency_conflict", repr(first))

        second = self._call_approve(
            controller,
            self._approve_payload(purchase, key=key, client_nonce="B"),
        )
        self._assert_error_contains(second, "idempotency_conflict")
        self.assertEqual(len(self._face_lines_for_purchase(purchase)), 1)
        self.assertEqual(len(self._approved_txs_for_purchase(purchase)), 1)

    def test_purchase_reject_is_backoffice_only_for_mobile_manager(self):
        controller, _manager, _session = self._admin_controller("admin-reject-backoffice-only-h0c@example.com")
        _carnet_type, _partner, purchase = self._create_submitted_purchase("reject-backoffice-only-h0c")

        response = self._call_reject(
            controller,
            self._reject_payload(purchase, key="reject-backoffice-only-h0c"),
        )
        self._assert_error_contains(response, "back-office")
        purchase.invalidate_recordset(["state", "rejected_by", "rejection_reason"])
        self.assertEqual(purchase.state, "submitted")
        self.assertFalse(purchase.rejected_by)
        self.assertFalse(purchase.rejection_reason)
        self.assertFalse(self._face_lines_for_purchase(purchase))
        self.assertFalse(self._approved_txs_for_purchase(purchase))

