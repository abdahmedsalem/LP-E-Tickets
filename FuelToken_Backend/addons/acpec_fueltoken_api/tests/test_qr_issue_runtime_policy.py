# -*- coding: utf-8 -*-
import base64
from types import SimpleNamespace
from unittest.mock import patch

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
            "login": login,
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
            "action_code": ("MISSING_ACTION_CODE", "INVALID_ACTION_CODE_KEY"),
            "Device mobile en attente de validation": ("DEVICE_PENDING_TRUST",),
            "PIN mobile invalide": ("INVALID_ACTION_CODE", "ACTION_CODE_DENIED"),
            "Clé PIN action invalide": ("INVALID_ACTION_CODE_KEY",),
        }

        if expected in sensitive_expected_codes:
            self.assertIn(code, sensitive_expected_codes[expected])
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
        controller, user, _session, carnet_type, _purchase, face_line, wallet = self._controller_with_stock(
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

        face_line.invalidate_recordset(["qty_available"])
        self.assertEqual(face_line.qty_available, face_line.qty_initial - 2)

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
