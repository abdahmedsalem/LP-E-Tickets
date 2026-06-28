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
class TestCarnetTransferRuntimePolicy(TransactionCase):
    # Runtime policy coverage for /mobile/carnets/transfer.
    # The fixture builds one intact carnet for the source mobile user,
    # creates a real recipient mobile user, then calls the real controller
    # and real acpec.fuel.carnet.transfer.action_confirm() path.

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.company = cls.env.company

    def _create_unique_carnet_type(self):
        carnet_model = self.env["acpec.fuel.carnet.type"].sudo()
        face_count = 10
        for face_value in range(940001, 940501):
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
        self.fail("Impossible de créer un type de carnet isolé pour le test transfert.")

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

    def _normalize_phone(self, raw_phone):
        # Use already-normalized Mauritanian mobile logins: 8 digits starting with 2, 3, or 4.
        # The runtime endpoint will parse recipient_phone and keep the same login.
        return raw_phone

    def _create_mobile_user(self, raw_phone, name_suffix):
        login = self._normalize_phone(raw_phone)
        user_model = self.env["res.users"].sudo().with_context(
            acpec_mobile_allow_password_write=True,
            no_reset_password=True,
        )
        user = user_model.create({
            "name": "Mobile %s" % name_suffix,
            "login": login,
            "mobile_phone": login,
            "email": "%s@example.test" % login.replace("+", "").replace(" ", "").replace("-", ""),
            "active": True,
            "company_id": self.company.id,
            "company_ids": [(6, 0, [self.company.id])],
            "mobile_only": True,
            "mobile_state": "approved",
            "password": user_model._acpec_mobile_unusable_password(),
            "group_ids": [(6, 0, self._mobile_group_ids())],
        })
        user.set_mobile_pin("1234")
        return user, login

    def _controller_for_source(self, raw_source_phone, trusted=True):
        source_user, source_login = self._create_mobile_user(raw_source_phone, "Source %s" % raw_source_phone)
        token_data = self.env["acpec.mobile.session"].sudo().create_for_user(source_user, {
            "device_uid": "dev-transfer-%s" % source_login.replace("+", "").replace(" ", "").replace("-", ""),
            "platform": "android",
        })
        session = token_data["session"]
        if trusted:
            session.action_trust_device()

        controller = AcpecFuelTokenMobileApi()
        controller._test_env = self.env
        controller._get_mobile_session = lambda required=True: session
        return controller, source_user, source_login, session

    def _create_source_stock(self, source_user):
        carnet_type = self._create_unique_carnet_type()
        purchase = self.env["acpec.fuel.purchase"].sudo().create({
            "partner_id": source_user.partner_id.id,
            "company_id": self.company.id,
            "payment_reference": "PAY-CARNET-TRANSFER-24E",
        })
        self.env["acpec.fuel.purchase.line"].sudo().create({
            "purchase_id": purchase.id,
            "carnet_type_id": carnet_type.id,
            "carnet_qty": 1,
        })
        attachment = self.env["ir.attachment"].sudo().create({
            "name": "preuve.pdf",
            "datas": base64.b64encode(b"%PDF-1.4\npreuve carnet transfer 24E\n").decode("ascii"),
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
            ("wallet_id.partner_id", "=", source_user.partner_id.id),
        ], limit=1)
        if not face_line:
            face_line = self.env["acpec.fuel.face.line"].sudo().search([
                ("purchase_id", "=", purchase.id),
            ], limit=1)
        self.assertTrue(face_line)
        self.assertEqual(face_line.carnet_type_id.id, carnet_type.id)
        self.assertEqual(face_line.qty_available, carnet_type.face_count)
        self.assertEqual(face_line.qty_initial, carnet_type.face_count)

        source_wallet = self.env["acpec.fuel.wallet"].sudo().get_or_create(source_user.partner_id, self.company)
        self.assertEqual(face_line.wallet_id.id, source_wallet.id)
        return carnet_type, purchase, face_line, source_wallet

    def _controller_with_transfer_fixture(self, suffix, trusted=True):
        source_raw = "48%06d" % suffix
        recipient_raw = "49%06d" % suffix

        controller, source_user, source_login, session = self._controller_for_source(
            source_raw,
            trusted=trusted,
        )
        recipient_user, recipient_login = self._create_mobile_user(
            recipient_raw,
            "Recipient %s" % recipient_raw,
        )
        carnet_type, purchase, face_line, source_wallet = self._create_source_stock(source_user)
        dest_wallet = self.env["acpec.fuel.wallet"].sudo().get_or_create(recipient_user.partner_id, self.company)
        return (
            controller,
            source_user,
            source_login,
            recipient_user,
            recipient_login,
            session,
            carnet_type,
            purchase,
            face_line,
            source_wallet,
            dest_wallet,
        )

    def _payload(self, recipient_login, face_line, key="carnet-transfer-runtime-key", carnet_qty=1, **extra):
        payload = {
            "recipient_phone": recipient_login,
            "lines": [{
                "face_line_id": face_line.id,
                "carnet_qty": carnet_qty,
            }],
            "action_code": "1234",
            "idempotency_key": key,
        }
        payload.update(extra)
        return payload

    def _call_transfer_carnets(self, controller, payload):
        fake_request = SimpleNamespace(env=self.env)
        with patch.object(api_mobile_module, "request", fake_request):
            return controller.transfer_carnets(**payload)

    def _call_transfer_list(self, controller, payload=None):
        fake_request = SimpleNamespace(env=self.env)
        with patch.object(api_mobile_module, "request", fake_request):
            return controller.transfer_list(**(payload or {}))

    def _assert_error_contains(self, response, expected):
        self.assertIn("success", repr(response))
        self.assertIn("False", repr(response))

        error = response.get("error", {}) if isinstance(response, dict) else {}
        code = error.get("code")
        public_message = error.get("message") or ""

        sensitive_expected_codes = {
            "action_code": ("ACTION_REFUSED",),
            "Device mobile en attente de validation": ("DEVICE_NOT_ALLOWED",),
            "PIN mobile invalide": ("ACTION_REFUSED",),
            "Clé PIN action invalide": ("ACTION_REFUSED",),
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

    def _transfer_by_key(self, source_wallet, key):
        return self.env["acpec.fuel.carnet.transfer"].sudo().search([
            ("source_wallet_id", "=", source_wallet.id),
            ("idempotency_key", "=", key),
        ])

    def _dest_face_line_for_transfer(self, transfer):
        return transfer.line_ids.mapped("dest_face_line_id")

    def test_transfer_carnets_requires_action_code_only(self):
        (
            controller, _source_user, _source_login, _recipient_user, recipient_login,
            _session, _carnet_type, _purchase, face_line, source_wallet, _dest_wallet,
        ) = self._controller_with_transfer_fixture(24001)

        missing = self._payload(recipient_login, face_line, key="transfer-missing-action-code")
        missing.pop("action_code")
        self._assert_error_contains(
            self._call_transfer_carnets(controller, missing),
            "action_code",
        )
        self.assertFalse(self._transfer_by_key(source_wallet, "transfer-missing-action-code"))

        for alias in ("action_pin", "pin", "secret_code"):
            key = "transfer-alias-%s" % alias
            payload = self._payload(recipient_login, face_line, key=key)
            payload.pop("action_code")
            payload[alias] = "1234"
            self._assert_error_contains(
                self._call_transfer_carnets(controller, payload),
                "action_code",
            )
            self.assertFalse(self._transfer_by_key(source_wallet, key))

    def test_transfer_carnets_requires_idempotency_key(self):
        (
            controller, _source_user, _source_login, _recipient_user, recipient_login,
            _session, _carnet_type, _purchase, face_line, source_wallet, _dest_wallet,
        ) = self._controller_with_transfer_fixture(24002)

        payload = self._payload(recipient_login, face_line, key="transfer-will-be-removed")
        payload.pop("idempotency_key")
        self._assert_error_contains(
            self._call_transfer_carnets(controller, payload),
            "idempotency_key",
        )
        self.assertFalse(self._transfer_by_key(source_wallet, "transfer-will-be-removed"))

    def test_transfer_carnets_unknown_recipient_uses_transfer_refused(self):
        (
            controller, _source_user, _source_login, _recipient_user, _recipient_login,
            _session, _carnet_type, _purchase, face_line, source_wallet, _dest_wallet,
        ) = self._controller_with_transfer_fixture(24091)
        key = 'carnet-transfer-unknown-recipient-h5b'
        response = self._call_transfer_carnets(
            controller,
            self._payload('49999991', face_line, key=key),
        )
        self.assertFalse(response['ok'])
        self.assertEqual(response['error']['code'], 'TRANSFER_REFUSED')
        self.assertTrue(str(response['error'].get('reference') or '').startswith('SEC-'))
        self.assertNotIn('49999991', repr(response))
        self.assertFalse(self._transfer_by_key(source_wallet, key))

    def test_transfer_carnets_replays_same_payload_for_same_idempotency_key(self):
        (
            controller, source_user, _source_login, _recipient_user, recipient_login,
            _session, carnet_type, _purchase, face_line, source_wallet, dest_wallet,
        ) = self._controller_with_transfer_fixture(24003)
        key = "carnet-transfer-replay-key-24e"
        payload = self._payload(recipient_login, face_line, key=key)

        first_response = self._call_transfer_carnets(controller, dict(payload))
        second_response = self._call_transfer_carnets(controller, dict(payload))

        transfers = self._transfer_by_key(source_wallet, key)
        self.assertEqual(len(transfers), 1)
        transfer = transfers
        self.assertIn(str(transfer.id), repr(first_response))
        self.assertIn(str(transfer.id), repr(second_response))
        self.assertEqual(transfer.state, "confirmed")
        self.assertEqual(transfer.confirmed_by.id, source_user.id)
        self.assertEqual(transfer.mobile_session_id.id, _session.id)
        self.assertEqual(transfer.device_uid, _session.device_uid)

        txs = self.env['acpec.fuel.transaction'].sudo().search([
            ('transfer_id', '=', transfer.id),
        ])
        self.assertEqual(len(txs), 2)
        self.assertEqual(set(txs.mapped('actor_user_id').ids), {source_user.id})
        self.assertEqual(set(txs.mapped('mobile_session_id').ids), {_session.id})
        self.assertEqual(set(txs.mapped('device_uid')), {_session.device_uid})

        self.assertEqual(transfer.face_qty_total, carnet_type.face_count)
        self.assertTrue(transfer.request_hash)

        face_line.invalidate_recordset(["wallet_id", "qty_initial", "qty_available"])
        self.assertEqual(face_line.wallet_id.id, dest_wallet.id)
        self.assertEqual(face_line.qty_initial, carnet_type.face_count)
        self.assertEqual(face_line.qty_available, carnet_type.face_count)

        dest_lines = self._dest_face_line_for_transfer(transfer)
        self.assertEqual(len(dest_lines), 1)
        self.assertEqual(dest_lines.id, face_line.id)
        self.assertEqual(dest_lines.wallet_id.id, dest_wallet.id)
        self.assertEqual(dest_lines.qty_initial, carnet_type.face_count)
        self.assertEqual(dest_lines.qty_available, carnet_type.face_count)

        tx_lines = txs.mapped("line_ids")
        self.assertTrue(tx_lines)
        self.assertEqual(set(tx_lines.mapped("face_line_id").ids), {face_line.id})

    def test_transfer_carnets_moves_same_face_line_identity_to_destination_wallet(self):
        (
            controller, _source_user, _source_login, _recipient_user, recipient_login,
            _session, carnet_type, _purchase, face_line, source_wallet, dest_wallet,
        ) = self._controller_with_transfer_fixture(24340)
        key = "carnet-transfer-move-identity-34c"
        original_face_line_id = face_line.id
        original_carnet_no = face_line.carnet_no
        original_carnet_short_code = face_line.carnet_short_code
        original_qty_initial = face_line.qty_initial
        original_qty_available = face_line.qty_available

        response = self._call_transfer_carnets(
            controller,
            self._payload(recipient_login, face_line, key=key),
        )

        transfer = self._transfer_by_key(source_wallet, key)
        self.assertEqual(len(transfer), 1)
        self.assertIn(str(transfer.id), repr(response))

        face_line.invalidate_recordset([
            "wallet_id",
            "carnet_no",
            "carnet_short_code",
            "qty_initial",
            "qty_available",
        ])
        self.assertEqual(face_line.id, original_face_line_id)
        self.assertEqual(face_line.wallet_id.id, dest_wallet.id)
        self.assertEqual(face_line.carnet_no, original_carnet_no)
        self.assertEqual(face_line.carnet_short_code, original_carnet_short_code)
        self.assertEqual(face_line.qty_initial, original_qty_initial)
        self.assertEqual(face_line.qty_available, original_qty_available)

        dest_lines = self._dest_face_line_for_transfer(transfer)
        self.assertEqual(dest_lines.id, original_face_line_id)

        source_remaining = self.env["acpec.fuel.face.line"].sudo().search([
            ("id", "=", original_face_line_id),
            ("wallet_id", "=", source_wallet.id),
        ])
        self.assertFalse(source_remaining)

    def test_transfer_carnets_rejects_same_key_with_different_payload(self):
        (
            controller, _source_user, _source_login, _recipient_user, recipient_login,
            _session, carnet_type, _purchase, face_line, source_wallet, _dest_wallet,
        ) = self._controller_with_transfer_fixture(24004)
        key = "carnet-transfer-conflict-key-24e"

        first = self._call_transfer_carnets(
            controller,
            self._payload(recipient_login, face_line, key=key, note="A"),
        )
        self.assertNotIn("idempotency_conflict", repr(first))

        second = self._call_transfer_carnets(
            controller,
            self._payload(recipient_login, face_line, key=key, note="B"),
        )
        self._assert_error_contains(second, "idempotency_conflict")

        transfers = self._transfer_by_key(source_wallet, key)
        self.assertEqual(len(transfers), 1)
        self.assertEqual(transfers.face_qty_total, carnet_type.face_count)

    def test_transfer_carnets_requires_trusted_device(self):
        (
            controller, _source_user, _source_login, _recipient_user, recipient_login,
            _session, _carnet_type, _purchase, face_line, source_wallet, _dest_wallet,
        ) = self._controller_with_transfer_fixture(24005, trusted=False)
        key = "carnet-transfer-untrusted-device-key-24e"

        response = self._call_transfer_carnets(
            controller,
            self._payload(recipient_login, face_line, key=key),
        )
        self._assert_error_contains(response, "Device mobile en attente de validation")
        self.assertFalse(self._transfer_by_key(source_wallet, key))
    def test_transfer_list_is_limited_to_current_company(self):
        (
            controller, source_user, _source_login, _recipient_user, recipient_login,
            _session, _carnet_type, _purchase, face_line, source_wallet, _dest_wallet,
        ) = self._controller_with_transfer_fixture(24030)

        key = "carnet-transfer-list-company-filter-27b"
        same_company_note = "same-company-transfer-visible-27b"
        payload = self._payload(
            recipient_login,
            face_line,
            key=key,
            note=same_company_note,
        )
        self._call_transfer_carnets(controller, payload)
        same_company_transfer = self._transfer_by_key(source_wallet, key)
        self.assertEqual(len(same_company_transfer), 1)

        other_company = self.env["res.company"].sudo().create({
            "name": "Patch27B Other Transfer Company",
        })
        foreign_partner = self.env["res.partner"].sudo().create({
            "name": "Patch27B Foreign Transfer Partner",
        })
        source_wallet_other_company = self.env["acpec.fuel.wallet"].sudo().get_or_create(
            source_user.partner_id,
            other_company,
        )
        dest_wallet_other_company = self.env["acpec.fuel.wallet"].sudo().get_or_create(
            foreign_partner,
            other_company,
        )
        foreign_note = "foreign-company-transfer-must-not-leak-27b"
        foreign_transfer = self.env["acpec.fuel.carnet.transfer"].sudo().create({
            "source_wallet_id": source_wallet_other_company.id,
            "dest_wallet_id": dest_wallet_other_company.id,
            "company_id": other_company.id,
            "note": foreign_note,
            "idempotency_key": "foreign-company-transfer-key-27b",
        })
        self.assertEqual(foreign_transfer.source_partner_id.id, source_user.partner_id.id)
        self.assertNotEqual(foreign_transfer.company_id.id, self.company.id)

        response = self._call_transfer_list(controller, {})
        response_repr = repr(response)

        self.assertIn(same_company_note, response_repr)
        self.assertNotIn(foreign_note, response_repr)
