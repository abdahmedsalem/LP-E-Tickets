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
class TestQrRetirerRuntimePolicy(TransactionCase):
    # Runtime policy coverage for /mobile/qr/retirer.
    # The fixture builds real approved stock, issues a real source QR,
    # then calls the real controller and real action_retirer_to_child() path.

    SOURCE_QTY = 4

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.company = cls.env.company

    def _create_unique_carnet_type(self):
        carnet_model = self.env["acpec.fuel.carnet.type"].sudo()
        face_count = 10
        for face_value in range(920001, 920401):
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
        self.fail("Impossible de créer un type de carnet isolé pour le test QR retirer.")

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
        purchase = self.env["acpec.fuel.purchase"]._create_internal({
            "partner_id": user.partner_id.id,
            "company_id": self.company.id,
            "payment_reference": "PAY-QR-RETIRER-24C",
        })
        self.env["acpec.fuel.purchase.line"]._create_internal({
            "purchase_id": purchase.id,
            "carnet_type_id": carnet_type.id,
            "carnet_qty": carnet_qty,
        })
        attachment = self.env["ir.attachment"].sudo().create({
            "name": "preuve.pdf",
            "datas": base64.b64encode(b"%PDF-1.4\npreuve qr retirer 24C\n").decode("ascii"),
            "mimetype": "application/pdf",
            "res_model": purchase._name,
            "res_id": purchase.id,
            "type": "binary",
        })
        purchase._write_proof_internal({"proof_attachment_ids": [(4, attachment.id)]})
        purchase.action_submit()
        purchase.action_approve()
        purchase._create_face_lines_after_approval()

        face_line = self.env["acpec.fuel.face.line"].sudo().search([
            ("purchase_id", "=", purchase.id),
        ], limit=1)
        self.assertTrue(face_line)
        self.assertGreaterEqual(face_line.qty_available, self.SOURCE_QTY)

        wallet = self.env["acpec.fuel.wallet"].sudo().get_or_create(user.partner_id, self.company)
        return carnet_type, purchase, face_line, wallet

    def _controller_with_source_qr(self, login, trusted=True):
        controller, user, session = self._controller_for_user(login, trusted=trusted)
        carnet_type, purchase, face_line, wallet = self._create_available_stock(user)
        source_qr = self.env["acpec.fuel.qr"].sudo().issue_from_available(
            wallet,
            [{"carnet_type_id": carnet_type.id, "qty": self.SOURCE_QTY}],
            idempotency_key="source-%s" % login,
            request_hash="source-hash-%s" % login,
        )
        self.assertEqual(source_qr.state, "active")
        self.assertEqual(source_qr.face_qty_total, self.SOURCE_QTY)
        self.assertTrue(source_qr.line_ids)
        return controller, user, session, carnet_type, purchase, face_line, wallet, source_qr

    def _payload(self, source_qr, key="qr-retirer-runtime-key", qty=1, **extra):
        source_line = source_qr.line_ids.filtered(lambda line: line.state == "active")[:1]
        self.assertTrue(source_line)
        payload = {
            "public_code": source_qr.public_code,
            "lines": [{
                "qr_line_id": source_line.id,
                "qty": qty,
            }],
            "action_code": "1234",
            "idempotency_key": key,
        }
        payload.update(extra)
        return payload

    def _call_retirer_qr(self, controller, payload):
        fake_request = SimpleNamespace(env=self.env)
        with patch.object(api_mobile_module, "request", fake_request):
            return controller.retirer_qr(**payload)

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

    def _retirer_tx_by_key(self, source_qr, key):
        return self.env["acpec.fuel.transaction"].sudo().search([
            ("transaction_type", "=", "retirer_qr"),
            ("parent_qr_id", "=", source_qr.id),
            ("idempotency_key", "=", key),
        ])

    def _child_qr_by_key(self, source_qr, key):
        tx = self._retirer_tx_by_key(source_qr, key)
        return tx.qr_id

    def test_retirer_qr_requires_action_code_only(self):
        controller, _user, _session, _carnet_type, _purchase, _face_line, _wallet, source_qr = self._controller_with_source_qr(
            "qr-retirer-action-code-24c@example.com",
        )

        missing = self._payload(source_qr, key="retirer-missing-action-code")
        missing.pop("action_code")
        self._assert_error_contains(
            self._call_retirer_qr(controller, missing),
            "action_code",
        )
        self.assertFalse(self._retirer_tx_by_key(source_qr, "retirer-missing-action-code"))

        for alias in ("action_pin", "pin", "secret_code"):
            key = "retirer-alias-%s" % alias
            payload = self._payload(source_qr, key=key)
            payload.pop("action_code")
            payload[alias] = "1234"
            self._assert_error_contains(
                self._call_retirer_qr(controller, payload),
                "action_code",
            )
            self.assertFalse(self._retirer_tx_by_key(source_qr, key))

    def test_retirer_qr_requires_idempotency_key(self):
        controller, _user, _session, _carnet_type, _purchase, _face_line, _wallet, source_qr = self._controller_with_source_qr(
            "qr-retirer-idempotency-required-24c@example.com",
        )

        payload = self._payload(source_qr, key="retirer-will-be-removed")
        payload.pop("idempotency_key")
        self._assert_error_contains(
            self._call_retirer_qr(controller, payload),
            "idempotency_key",
        )
        self.assertFalse(self._retirer_tx_by_key(source_qr, "retirer-will-be-removed"))

    def test_retirer_qr_replays_same_payload_for_same_idempotency_key(self):
        controller, user, session, _carnet_type, _purchase, _face_line, wallet, source_qr = self._controller_with_source_qr(
            "qr-retirer-replay-24c@example.com",
        )
        key = "qr-retirer-replay-key-24c"
        payload = self._payload(source_qr, key=key, qty=1)

        first_response = self._call_retirer_qr(controller, dict(payload))
        second_response = self._call_retirer_qr(controller, dict(payload))

        txs = self._retirer_tx_by_key(source_qr, key)
        self.assertEqual(len(txs), 1)
        child = txs.qr_id
        self.assertTrue(child)
        self.assertIn(str(child.id), repr(first_response))
        self.assertIn(str(child.id), repr(second_response))
        self.assertEqual(child.parent_id.id, source_qr.id)
        self.assertEqual(child.face_qty_total, 1)
        self.assertTrue(txs.request_hash)
        self.assertEqual(txs.partner_id.id, wallet.partner_id.id)
        self.assertEqual(txs.actor_partner_id.id, user.partner_id.id)
        self.assertEqual(txs.actor_user_id.id, user.id)
        self.assertEqual(txs.mobile_session_id.id, session.id)
        self.assertEqual(txs.device_uid, session.device_uid)
        self.assertFalse(txs.counterparty_partner_id)

        source_qr.invalidate_recordset()
        self.assertEqual(source_qr.face_qty_total, self.SOURCE_QTY - 1)

    def test_retirer_qr_rejects_same_key_with_different_payload(self):
        controller, _user, _session, _carnet_type, _purchase, _face_line, _wallet, source_qr = self._controller_with_source_qr(
            "qr-retirer-conflict-24c@example.com",
        )
        key = "qr-retirer-conflict-key-24c"

        first = self._call_retirer_qr(controller, self._payload(source_qr, key=key, qty=1))
        self.assertNotIn("idempotency_conflict", repr(first))

        second = self._call_retirer_qr(controller, self._payload(source_qr, key=key, qty=2))
        self._assert_error_contains(second, "idempotency_conflict")

        txs = self._retirer_tx_by_key(source_qr, key)
        self.assertEqual(len(txs), 1)
        self.assertEqual(txs.qr_id.face_qty_total, 1)

    def test_retirer_qr_requires_trusted_device(self):
        controller, _user, _session, _carnet_type, _purchase, _face_line, _wallet, source_qr = self._controller_with_source_qr(
            "qr-retirer-untrusted-device-24c@example.com",
            trusted=False,
        )
        key = "qr-retirer-untrusted-device-key-24c"
        response = self._call_retirer_qr(
            controller,
            self._payload(source_qr, key=key),
        )
        self._assert_error_contains(response, "Device mobile en attente de validation")
        self.assertFalse(self._retirer_tx_by_key(source_qr, key))
