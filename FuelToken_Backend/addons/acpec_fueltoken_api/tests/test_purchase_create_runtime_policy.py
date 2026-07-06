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

from odoo.addons.acpec_fueltoken_api.controllers import api_mobile as api_mobile_module
from odoo.addons.acpec_fueltoken_api.controllers.api_mobile import AcpecFuelTokenMobileApi


@tagged("post_install", "-at_install")
class TestPurchaseCreateRuntimePolicy(TransactionCase):
    # Runtime policy coverage for /mobile/purchases/create.
    # The test calls the real controller method and purchase create_from_api().
    # Only the HTTP request object is replaced by a test double exposing request.env.

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.company = cls.env.company
        cls.carnet_type = cls._ensure_carnet_type()

    @classmethod
    def _ensure_carnet_type(cls):
        model = cls.env["acpec.fuel.carnet.type"].sudo()
        existing = model.search([
            ("company_id", "in", [False, cls.company.id]),
            ("active", "=", True),
        ], limit=1)
        if existing:
            return existing

        vals = {}
        fields = model._fields
        defaults = {
            "name": "Runtime C10 100",
            "code": "RT24A-C10-100",
            "company_id": cls.company.id,
            "currency_id": cls.company.currency_id.id,
            "face_value": 100,
            "face_count": 10,
            "validity_days": 30,
            "active": True,
        }
        for key, value in defaults.items():
            if key in fields:
                vals[key] = value

        return model.create(vals)

    def _mobile_group_ids(self):
        xmlids = [
            "base.group_portal",
            "acpec_mobile_auth.group_mobile_auth_user",
            "acpec_fueltoken_base.group_fuel_user",
        ]
        ids = []
        for xmlid in xmlids:
            group = self.env.ref(xmlid, raise_if_not_found=False)
            if group:
                ids.append(group.id)
        return ids

    def _create_mobile_user(self, login):
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
            "group_ids": [(6, 0, self._mobile_group_ids())],
        })
        user.set_mobile_pin("1234")
        return user

    def _controller_for_user(self, login="purchase-runtime-24a@example.com", trusted=True):
        user = self._create_mobile_user(login)
        token_data = self.env["acpec.mobile.session"].sudo().create_for_user(user, {
            "device_uid": login.replace("@", "-"),
            "platform": "android",
        })
        session = token_data["session"]
        if trusted:
            session.action_trust_device()

        controller = AcpecFuelTokenMobileApi()
        controller._test_env = self.env
        controller._get_mobile_session = lambda required=True: session
        return controller, user, session

    def _proof_pdf(self):
        return base64.b64encode(b"%PDF-1.4\nruntime purchase proof\n").decode("ascii")

    def _payload(self, key="purchase-runtime-key", carnet_qty=1, **extra):
        payload = {
            "lines": [{
                "carnet_type_id": self.carnet_type.id,
                "carnet_qty": carnet_qty,
            }],
            "proof_filename": "preuve.pdf",
            "proof_data": self._proof_pdf(),
            "payment_reference": "PAY-RUNTIME-24A",
            "action_code": "1234",
            "idempotency_key": key,
        }
        payload.update(extra)
        return payload

    def _call_create_purchase(self, controller, payload):
        fake_request = SimpleNamespace(env=self.env)
        with patch.object(api_mobile_module, "request", fake_request):
            return controller.create_purchase(**payload)

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

    def _purchase_by_key(self, user, key):
        return self.env["acpec.fuel.purchase"].sudo().search([
            ("partner_id", "=", user.partner_id.id),
            ("idempotency_key", "=", key),
        ])

    def test_create_purchase_requires_action_code_only(self):
        controller, user, _session = self._controller_for_user("purchase-action-code-24a@example.com")

        missing = self._payload(key="missing-action-code")
        missing.pop("action_code")
        self._assert_error_contains(
            self._call_create_purchase(controller, missing),
            "action_code",
        )
        self.assertFalse(self._purchase_by_key(user, "missing-action-code"))

        for alias in ("action_pin", "pin", "secret_code"):
            payload = self._payload(key="alias-%s" % alias)
            payload.pop("action_code")
            payload[alias] = "1234"
            self._assert_error_contains(
                self._call_create_purchase(controller, payload),
                "action_code",
            )
            self.assertFalse(self._purchase_by_key(user, "alias-%s" % alias))

    def test_create_purchase_requires_idempotency_key(self):
        controller, user, _session = self._controller_for_user("purchase-idempotency-required-24a@example.com")
        before = self.env["acpec.fuel.purchase"].sudo().search_count([
            ("partner_id", "=", user.partner_id.id),
        ])

        payload = self._payload(key="will-be-removed")
        payload.pop("idempotency_key")
        self._assert_error_contains(
            self._call_create_purchase(controller, payload),
            "idempotency_key",
        )

        after = self.env["acpec.fuel.purchase"].sudo().search_count([
            ("partner_id", "=", user.partner_id.id),
        ])
        self.assertEqual(before, after)

    def test_create_purchase_replays_same_payload_for_same_idempotency_key(self):
        controller, user, session = self._controller_for_user("purchase-replay-24a@example.com")
        payload = self._payload(key="purchase-replay-key-24a")

        first_response = self._call_create_purchase(controller, dict(payload))
        second_response = self._call_create_purchase(controller, dict(payload))

        purchases = self._purchase_by_key(user, "purchase-replay-key-24a")
        self.assertEqual(len(purchases), 1)
        self.assertIn(str(purchases.id), repr(first_response))
        self.assertIn(str(purchases.id), repr(second_response))
        self.assertEqual(purchases.state, "submitted")
        self.assertTrue(purchases.request_hash)

        txs = self.env["acpec.fuel.transaction"].sudo().search([
            ("purchase_id", "=", purchases.id),
            ("transaction_type", "=", "purchase_submitted"),
        ])
        self.assertEqual(len(txs), 1)
        self.assertEqual(txs.partner_id.id, user.partner_id.id)
        self.assertEqual(txs.actor_partner_id.id, user.partner_id.id)
        self.assertEqual(txs.actor_user_id.id, user.id)
        self.assertEqual(txs.mobile_session_id.id, session.id)
        self.assertEqual(txs.device_uid, session.device_uid)
        self.assertFalse(txs.counterparty_partner_id)

    def test_create_purchase_rejects_same_key_with_different_payload(self):
        controller, user, _session = self._controller_for_user("purchase-conflict-24a@example.com")
        key = "purchase-conflict-key-24a"

        first = self._call_create_purchase(controller, self._payload(key=key, carnet_qty=1))
        self.assertNotIn("idempotency_conflict", repr(first))

        second = self._call_create_purchase(controller, self._payload(key=key, carnet_qty=2))
        self._assert_error_contains(second, "idempotency_conflict")

        purchases = self._purchase_by_key(user, key)
        self.assertEqual(len(purchases), 1)

    def test_create_purchase_requires_trusted_device(self):
        controller, user, _session = self._controller_for_user(
            "purchase-untrusted-device-24a@example.com",
            trusted=False,
        )
        response = self._call_create_purchase(
            controller,
            self._payload(key="purchase-untrusted-device-key-24a"),
        )
        self._assert_error_contains(response, "Device mobile en attente de validation")
        self.assertFalse(self._purchase_by_key(user, "purchase-untrusted-device-key-24a"))
