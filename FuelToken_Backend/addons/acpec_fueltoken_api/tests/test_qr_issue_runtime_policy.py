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
class TestQrIssueRuntimePolicy(TransactionCase):
    # Runtime policy coverage for /mobile/qr/issue.
    # The fixture builds real approved stock for the mobile user's partner,
    # then calls the real controller and real issue_from_available() path.

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.company = cls.env.company

    def _create_unique_carnet_type(self):
        carnet_model = self.env["acpec.fuel.carnet.type"].sudo()
        face_count = 10
        for face_value in range(910001, 910301):
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
        self.fail("Impossible de créer un type de carnet isolé pour le test QR.")

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
            "acpec_mobile_only": True,
            "acpec_mobile_state": "approved",
            "password": user_model._acpec_mobile_unusable_password(),
            "group_ids": [(6, 0, self._mobile_group_ids())],
        })
        user.set_mobile_pin("1234")
        return user

    def _controller_for_user(self, login, trusted=True):
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

    def _create_available_stock(self, user, carnet_qty=1):
        carnet_type = self._create_unique_carnet_type()
        purchase = self.env["acpec.fuel.purchase"].sudo().create({
            "partner_id": user.partner_id.id,
            "company_id": self.company.id,
            "payment_reference": "PAY-QR-24B",
        })
        self.env["acpec.fuel.purchase.line"].sudo().create({
            "purchase_id": purchase.id,
            "carnet_type_id": carnet_type.id,
            "carnet_qty": carnet_qty,
        })
        attachment = self.env["ir.attachment"].sudo().create({
            "name": "preuve.pdf",
            "datas": base64.b64encode(b"%PDF-1.4\npreuve qr issue 24B\n").decode("ascii"),
            "mimetype": "application/pdf",
            "res_model": purchase._name,
            "res_id": purchase.id,
            "type": "binary",
        })
        purchase.write({"proof_attachment_ids": [(4, attachment.id)]})
        purchase.action_submit()
        purchase.action_approve()
        purchase._create_face_lines_after_approval()

        face_line = self.env["acpec.fuel.face.line"].sudo().search([
            ("purchase_id", "=", purchase.id),
        ], limit=1)
        self.assertTrue(face_line)
        self.assertGreater(face_line.qty_available, 0)

        wallet = self.env["acpec.fuel.wallet"].sudo().get_or_create(user.partner_id, self.company)
        return carnet_type, purchase, face_line, wallet

    def _controller_with_stock(self, login, trusted=True, carnet_qty=1):
        controller, user, session = self._controller_for_user(login, trusted=trusted)
        carnet_type, purchase, face_line, wallet = self._create_available_stock(user, carnet_qty=carnet_qty)
        return controller, user, session, carnet_type, purchase, face_line, wallet

    def _payload(self, carnet_type, key="qr-issue-runtime-key", qty=1, **extra):
        payload = {
            "lines": [{
                "carnet_type_id": carnet_type.id,
                "qty": qty,
            }],
            "action_code": "1234",
            "idempotency_key": key,
        }
        payload.update(extra)
        return payload

    def _payload_face_line(self, face_line, key="qr-issue-explicit-face-line-key", qty=1, **extra):
        payload = {
            "lines": [{
                "face_line_id": face_line.id,
                "qty": qty,
            }],
            "action_code": "1234",
            "idempotency_key": key,
        }
        payload.update(extra)
        return payload

    def _call_issue_qr(self, controller, payload):
        fake_request = SimpleNamespace(env=self.env)
        with patch.object(api_mobile_module, "request", fake_request):
            return controller.issue_qr(**payload)

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

    def _qr_by_key(self, wallet, key):
        return self.env["acpec.fuel.qr"].sudo().search([
            ("wallet_id", "=", wallet.id),
            ("idempotency_key", "=", key),
        ])

    def test_issue_qr_requires_action_code_only(self):
        controller, user, _session, carnet_type, _purchase, _face_line, wallet = self._controller_with_stock(
            "qr-action-code-24b@example.com",
        )

        missing = self._payload(carnet_type, key="qr-missing-action-code")
        missing.pop("action_code")
        self._assert_error_contains(
            self._call_issue_qr(controller, missing),
            "action_code",
        )
        self.assertFalse(self._qr_by_key(wallet, "qr-missing-action-code"))

        for alias in ("action_pin", "pin", "secret_code"):
            key = "qr-alias-%s" % alias
            payload = self._payload(carnet_type, key=key)
            payload.pop("action_code")
            payload[alias] = "1234"
            self._assert_error_contains(
                self._call_issue_qr(controller, payload),
                "action_code",
            )
            self.assertFalse(self._qr_by_key(wallet, key))

    def test_issue_qr_requires_idempotency_key(self):
        controller, user, _session, carnet_type, _purchase, _face_line, wallet = self._controller_with_stock(
            "qr-idempotency-required-24b@example.com",
        )

        before = self.env["acpec.fuel.qr"].sudo().search_count([
            ("wallet_id", "=", wallet.id),
        ])
        payload = self._payload(carnet_type, key="qr-will-be-removed")
        payload.pop("idempotency_key")
        self._assert_error_contains(
            self._call_issue_qr(controller, payload),
            "idempotency_key",
        )
        after = self.env["acpec.fuel.qr"].sudo().search_count([
            ("wallet_id", "=", wallet.id),
        ])
        self.assertEqual(before, after)

    def test_issue_qr_replays_same_payload_for_same_idempotency_key(self):
        controller, user, session, carnet_type, _purchase, face_line, wallet = self._controller_with_stock(
            "qr-replay-24b@example.com",
            carnet_qty=1,
        )
        key = "qr-replay-key-24b"
        payload = self._payload(carnet_type, key=key, qty=2)

        first_response = self._call_issue_qr(controller, dict(payload))
        second_response = self._call_issue_qr(controller, dict(payload))

        qrs = self._qr_by_key(wallet, key)
        self.assertEqual(len(qrs), 1)
        self.assertIn(str(qrs.id), repr(first_response))
        self.assertIn(str(qrs.id), repr(second_response))
        self.assertEqual(qrs.state, "active")
        self.assertEqual(qrs.face_qty_total, 2)
        self.assertTrue(qrs.request_hash)
        self.assertTrue(qrs.qr_numeric_code_hash)
        self.assertRegex(qrs._qr_numeric_code_display(), r'^\d{4}-\d{4}-\d{4}$')
        self.assertTrue(qrs.name)
        self.assertNotRegex(qrs.name or '', r'^\d{4}-\d{4}-\d{4}$')
        self.assertNotEqual(qrs.name, qrs._qr_numeric_code_display())
        self.assertNotIn(qrs._qr_numeric_code_display(), repr(first_response))
        self.assertNotIn('qr_numeric_code', repr(first_response))
        self.assertNotIn(qrs.qr_numeric_code_hash, repr(first_response))

        txs = self.env["acpec.fuel.transaction"].sudo().search([
            ("qr_id", "=", qrs.id),
            ("transaction_type", "=", "emission_qr"),
            ("wallet_id", "=", wallet.id),
        ])
        self.assertEqual(len(txs), 1)
        self.assertEqual(txs.partner_id.id, wallet.partner_id.id)
        self.assertEqual(txs.actor_partner_id.id, user.partner_id.id)
        self.assertEqual(txs.actor_user_id.id, user.id)
        self.assertEqual(txs.mobile_session_id.id, session.id)
        self.assertEqual(txs.device_uid, session.device_uid)
        self.assertFalse(txs.counterparty_partner_id)

        face_line.invalidate_recordset(["qty_available"])
        self.assertEqual(face_line.qty_available, face_line.qty_initial - 2)

    def test_issue_qr_can_use_explicit_face_line_id(self):
        controller, user, _session, carnet_type, purchase, _face_line, wallet = self._controller_with_stock(
            "qr-explicit-face-line-34b@example.com",
            carnet_qty=2,
        )
        face_lines = self.env["acpec.fuel.face.line"].sudo().search([
            ("purchase_id", "=", purchase.id),
        ], order="carnet_sequence,id")
        self.assertEqual(len(face_lines), 2)
        selected = face_lines[1]
        untouched = face_lines[0]
        selected_initial_available = selected.qty_available
        untouched_initial_available = untouched.qty_available

        response = self._call_issue_qr(
            controller,
            self._payload_face_line(selected, key="qr-explicit-face-line-34b", qty=3),
        )

        qrs = self._qr_by_key(wallet, "qr-explicit-face-line-34b")
        self.assertEqual(len(qrs), 1)
        self.assertIn(str(qrs.id), repr(response))
        self.assertEqual(qrs.face_qty_total, 3)
        self.assertEqual(qrs.line_ids.face_line_id.id, selected.id)

        selected.invalidate_recordset(["qty_available", "qty_qr_active"])
        untouched.invalidate_recordset(["qty_available", "qty_qr_active"])
        self.assertEqual(selected.qty_available, selected_initial_available - 3)
        self.assertEqual(selected.qty_qr_active, 3)
        self.assertEqual(untouched.qty_available, untouched_initial_available)
        self.assertEqual(untouched.qty_qr_active, 0)

    def test_issue_qr_rejects_explicit_foreign_face_line_id(self):
        controller, user, _session, carnet_type, _purchase, _face_line, wallet = self._controller_with_stock(
            "qr-explicit-foreign-owner-34b@example.com",
            carnet_qty=1,
        )
        other_controller, other_user, _other_session, _other_carnet_type, _other_purchase, other_face_line, _other_wallet = self._controller_with_stock(
            "qr-explicit-foreign-source-34b@example.com",
            carnet_qty=1,
        )

        response = self._call_issue_qr(
            controller,
            self._payload_face_line(other_face_line, key="qr-explicit-foreign-34b", qty=1),
        )

        self._assert_error_contains(response, "Carnet indisponible")
        self.assertFalse(self._qr_by_key(wallet, "qr-explicit-foreign-34b"))

    def test_issue_qr_rejects_mixed_explicit_and_automatic_lines(self):
        controller, user, _session, carnet_type, purchase, _face_line, wallet = self._controller_with_stock(
            "qr-mixed-lines-34b@example.com",
            carnet_qty=2,
        )
        face_line = self.env["acpec.fuel.face.line"].sudo().search([
            ("purchase_id", "=", purchase.id),
        ], order="carnet_sequence,id", limit=1)
        payload = {
            "lines": [
                {"face_line_id": face_line.id, "qty": 1},
                {"carnet_type_id": carnet_type.id, "qty": 1},
            ],
            "action_code": "1234",
            "idempotency_key": "qr-mixed-lines-34b",
        }

        response = self._call_issue_qr(controller, payload)

        self._assert_error_contains(response, "melanger")
        self.assertFalse(self._qr_by_key(wallet, "qr-mixed-lines-34b"))

    def test_issue_qr_rejects_same_key_with_different_payload(self):
        controller, user, _session, carnet_type, _purchase, _face_line, wallet = self._controller_with_stock(
            "qr-conflict-24b@example.com",
            carnet_qty=1,
        )
        key = "qr-conflict-key-24b"

        first = self._call_issue_qr(controller, self._payload(carnet_type, key=key, qty=1))
        self.assertNotIn("idempotency_conflict", repr(first))

        second = self._call_issue_qr(controller, self._payload(carnet_type, key=key, qty=2))
        self._assert_error_contains(second, "idempotency_conflict")

        qrs = self._qr_by_key(wallet, key)
        self.assertEqual(len(qrs), 1)
        self.assertEqual(qrs.face_qty_total, 1)

    def test_issue_qr_requires_trusted_device(self):
        controller, user, _session, carnet_type, _purchase, _face_line, wallet = self._controller_with_stock(
            "qr-untrusted-device-24b@example.com",
            trusted=False,
        )
        key = "qr-untrusted-device-key-24b"
        response = self._call_issue_qr(
            controller,
            self._payload(carnet_type, key=key),
        )
        self._assert_error_contains(response, "Device mobile en attente de validation")
        self.assertFalse(self._qr_by_key(wallet, key))
