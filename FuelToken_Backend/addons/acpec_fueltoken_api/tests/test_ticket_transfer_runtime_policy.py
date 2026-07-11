# -*- coding: utf-8 -*-
import inspect
import base64
from types import SimpleNamespace
from unittest.mock import patch

from odoo.exceptions import AccessError
from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_fueltoken_api.controllers import api_mobile as api_mobile_module
from odoo.addons.acpec_fueltoken_api.controllers.api_mobile import AcpecFuelTokenMobileApi


@tagged("post_install", "-at_install")
class TestTicketTransferRuntimePolicy(TransactionCase):
    """Runtime policy coverage for /mobile/tickets/transfer."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.company = cls.env.company

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

    def _create_mobile_user(self, raw_phone, name_suffix):
        login = raw_phone
        user_model = self.env["res.users"].sudo().with_context(
            acpec_mobile_allow_password_write=True,
            no_reset_password=True,
        )
        user = user_model.create({
            "name": "Mobile Ticket %s" % name_suffix,
            "login": login,
            "mobile_phone": login,
            "email": "%s@example.test" % login,
            "active": True,
            "company_id": self.company.id,
            "company_ids": [(6, 0, [self.company.id])],
            "acpec_mobile_only": True,
            "acpec_mobile_state": "approved",
            "password": user_model._acpec_mobile_unusable_password(),
            "group_ids": [(6, 0, self._mobile_group_ids())],
        })
        user.set_mobile_pin("1234")
        return user, login

    def _controller_for_source(self, raw_source_phone, trusted=True):
        source_user, source_login = self._create_mobile_user(raw_source_phone, "Source %s" % raw_source_phone)
        token_data = self.env["acpec.mobile.session"].sudo().create_for_user(source_user, {
            "device_uid": "dev-ticket-transfer-%s" % source_login,
            "platform": "android",
        })
        session = token_data["session"]
        if trusted:
            session.action_trust_device()

        controller = AcpecFuelTokenMobileApi()
        controller._test_env = self.env
        controller._get_mobile_session = lambda required=True: session
        return controller, source_user, source_login, session

    def _create_unique_carnet_type(self):
        carnet_model = self.env["acpec.fuel.carnet.type"].sudo()
        face_count = 10
        for face_value in range(950001, 950701):
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
        self.fail("Impossible de créer un type de carnet isolé pour le test transfert tickets.")

    def _create_source_stock(self, source_user):
        carnet_type = self._create_unique_carnet_type()
        purchase = self.env["acpec.fuel.purchase"]._create_internal({
            "partner_id": source_user.partner_id.id,
            "company_id": self.company.id,
            "payment_reference": "PAY-TICKET-TRANSFER-I2",
        })
        self.env["acpec.fuel.purchase.line"]._create_internal({
            "purchase_id": purchase.id,
            "carnet_type_id": carnet_type.id,
            "carnet_qty": 1,
        })
        attachment = self.env["ir.attachment"].sudo().create({
            "name": "preuve-ticket-transfer.pdf",
            "datas": base64.b64encode(b"%PDF-1.4\npreuve ticket transfer I2\n").decode("ascii"),
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
            ("wallet_id.partner_id", "=", source_user.partner_id.id),
        ], limit=1)
        self.assertTrue(face_line)
        source_wallet = self.env["acpec.fuel.wallet"].sudo().get_or_create(source_user.partner_id, self.company)
        self.assertEqual(face_line.wallet_id.id, source_wallet.id)
        self.assertEqual(face_line.qty_initial, carnet_type.face_count)
        self.assertEqual(face_line.qty_available, carnet_type.face_count)
        return carnet_type, purchase, face_line, source_wallet

    def _controller_with_ticket_transfer_fixture(self, suffix, trusted=True):
        source_raw = "47%06d" % suffix
        recipient_raw = "46%06d" % suffix
        controller, source_user, source_login, session = self._controller_for_source(source_raw, trusted=trusted)
        recipient_user, recipient_login = self._create_mobile_user(recipient_raw, "Recipient %s" % recipient_raw)
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

    def _payload(self, recipient_login, face_line, key="ticket-transfer-runtime-key", qty=3, note="Motif transfert tickets I2", **extra):
        payload = {
            "recipient_phone": recipient_login,
            "lines": [{
                "face_line_id": face_line.id,
                "qty_tickets": qty,
            }],
            "action_code": "1234",
            "idempotency_key": key,
        }
        if note is not None:
            payload["note"] = note
        payload.update(extra)
        return payload

    def _call_transfer_tickets(self, controller, payload):
        fake_request = SimpleNamespace(env=self.env)
        with patch.object(api_mobile_module, "request", fake_request):
            return controller.transfer_tickets(**payload)

    def _assert_error_contains(self, response, expected):
        self.assertIn("success", repr(response))
        self.assertIn("False", repr(response))
        error = response.get("error", {}) if isinstance(response, dict) else {}
        code = error.get("code")
        public_message = error.get("message") or ""
        sensitive_expected_codes = {
            "action_code": ("ACTION_REFUSED", "MISSING_ACTION_CODE", "INVALID_ACTION_CODE_KEY"),
            "Device mobile en attente de validation": ("DEVICE_NOT_ALLOWED", "DEVICE_PENDING_TRUST"),
            "idempotency_conflict": ("REQUEST_REFUSED",),
        }
        if expected in sensitive_expected_codes:
            self.assertIn(code, sensitive_expected_codes[expected])
            self.assertTrue(str(error.get("reference") or "").startswith("SEC-"))
            if expected == "idempotency_conflict":
                self.assertEqual(public_message, "Cette demande ne peut pas être traitée.")
            else:
                self.assertNotIn(expected, public_message)
            return
        self.assertIn(expected, repr(response))

    def _transfer_by_key(self, source_wallet, key):
        return self.env["acpec.fuel.ticket.transfer"].sudo().search([
            ("source_wallet_id", "=", source_wallet.id),
            ("idempotency_key", "=", key),
        ])

    def test_j0_transfer_tickets_has_diagnostic_logging_hooks(self):
        source = inspect.getsource(AcpecFuelTokenMobileApi.transfer_tickets)
        self.assertIn("_log_api_diagnostic_in", source)
        self.assertIn("_log_api_diagnostic_out", source)
        self.assertIn("endpoint = 'mobile.tickets.transfer'", source)
        self.assertIn("operation = 'ticket_transfer'", source)
        self.assertIn("operation=operation", source)
        self.assertIn("endpoint=endpoint", source)
        self.assertIn("params=kwargs", source)

    def test_transfer_tickets_requires_action_code_only(self):
        (
            controller, _source_user, _source_login, _recipient_user, recipient_login,
            _session, _carnet_type, _purchase, face_line, source_wallet, _dest_wallet,
        ) = self._controller_with_ticket_transfer_fixture(25001)
        key = "ticket-transfer-missing-pin-i2"
        missing = self._payload(recipient_login, face_line, key=key)
        missing.pop("action_code")
        self._assert_error_contains(self._call_transfer_tickets(controller, missing), "action_code")
        self.assertFalse(self._transfer_by_key(source_wallet, key))

    def test_transfer_tickets_requires_idempotency_key(self):
        (
            controller, _source_user, _source_login, _recipient_user, recipient_login,
            _session, _carnet_type, _purchase, face_line, source_wallet, _dest_wallet,
        ) = self._controller_with_ticket_transfer_fixture(25002)
        payload = self._payload(recipient_login, face_line, key="ticket-transfer-no-key-i2")
        payload.pop("idempotency_key")
        self._assert_error_contains(self._call_transfer_tickets(controller, payload), "idempotency_key")
        self.assertFalse(self._transfer_by_key(source_wallet, "ticket-transfer-no-key-i2"))

    def test_transfer_tickets_unknown_recipient_uses_transfer_refused(self):
        (
            controller, _source_user, _source_login, _recipient_user, _recipient_login,
            _session, _carnet_type, _purchase, face_line, source_wallet, _dest_wallet,
        ) = self._controller_with_ticket_transfer_fixture(25003)
        key = "ticket-transfer-unknown-recipient-i2"
        response = self._call_transfer_tickets(
            controller,
            self._payload("46999999", face_line, key=key),
        )
        self.assertFalse(response["ok"])
        self.assertEqual(response["error"]["code"], "TRANSFER_REFUSED")
        self.assertTrue(str(response["error"].get("reference") or "").startswith("SEC-"))
        self.assertNotIn("46999999", repr(response))
        self.assertFalse(self._transfer_by_key(source_wallet, key))

    def test_transfer_tickets_replays_same_payload_for_same_idempotency_key(self):
        (
            controller, source_user, _source_login, _recipient_user, recipient_login,
            session, carnet_type, _purchase, face_line, source_wallet, dest_wallet,
        ) = self._controller_with_ticket_transfer_fixture(25004)
        key = "ticket-transfer-replay-key-i2"
        qty = 4
        payload = self._payload(recipient_login, face_line, key=key, qty=qty)

        first_response = self._call_transfer_tickets(controller, dict(payload))
        second_response = self._call_transfer_tickets(controller, dict(payload))

        transfers = self._transfer_by_key(source_wallet, key)
        self.assertEqual(len(transfers), 1)
        transfer = transfers
        self.assertIn(str(transfer.id), repr(first_response))
        self.assertIn(str(transfer.id), repr(second_response))
        self.assertEqual(transfer.state, "confirmed")
        self.assertEqual(transfer.confirmed_by.id, source_user.id)
        self.assertEqual(transfer.mobile_session_id.id, session.id)
        self.assertEqual(transfer.device_uid, session.device_uid)
        self.assertEqual(transfer.face_qty_total, qty)
        self.assertEqual(transfer.amount_total, qty * face_line.face_value)

        line = transfer.line_ids[0]
        dest_line = line.dest_face_line_id
        self.assertTrue(dest_line)
        self.assertNotEqual(dest_line.id, face_line.id)

        face_line.invalidate_recordset(["qty_initial", "qty_available", "qty_transferred_out", "wallet_id"])
        dest_line.invalidate_recordset(["qty_initial", "qty_available", "origin_face_line_id", "origin_ticket_transfer_line_id"])
        source_wallet.invalidate_recordset()
        dest_wallet.invalidate_recordset()

        self.assertEqual(face_line.wallet_id.id, source_wallet.id)
        self.assertEqual(face_line.qty_initial, carnet_type.face_count)
        self.assertEqual(face_line.qty_available, carnet_type.face_count - qty)
        self.assertEqual(face_line.qty_transferred_out, qty)
        self.assertEqual(dest_line.wallet_id.id, dest_wallet.id)
        self.assertEqual(dest_line.qty_initial, qty)
        self.assertEqual(dest_line.qty_available, qty)
        self.assertTrue(dest_line.is_transfer_fragment)
        self.assertEqual(dest_line.origin_face_line_id.id, face_line.id)
        self.assertEqual(dest_line.origin_ticket_transfer_line_id.id, line.id)
        self.assertTrue(dest_line.carnet_short_code)
        self.assertNotEqual(dest_line.carnet_short_code, face_line.carnet_short_code)
        self.assertEqual(source_wallet.balance, (carnet_type.face_count - qty) * face_line.face_value)
        self.assertEqual(dest_wallet.balance, qty * face_line.face_value)

        txs = self.env["acpec.fuel.transaction"].sudo().search([
            ("transaction_type", "=", "transfert_ticket"),
            ("ticket_transfer_id", "=", transfer.id),
        ])
        self.assertEqual(len(txs), 2)
        self.assertEqual(set(txs.mapped("wallet_id").ids), {source_wallet.id, dest_wallet.id})
        self.assertEqual(set(txs.mapped("actor_user_id").ids), {source_user.id})
        self.assertEqual(set(txs.mapped("actor_partner_id").ids), {source_user.partner_id.id})
        self.assertEqual(set(txs.mapped("counterparty_partner_id").ids), {_recipient_user.partner_id.id})
        self.assertEqual(set(txs.mapped("counterparty_user_id").ids), {_recipient_user.id})
        self.assertEqual(set(txs.mapped("mobile_session_id").ids), {session.id})
        self.assertEqual(set(txs.mapped("device_uid")), {session.device_uid})
        self.assertEqual(self.env["acpec.fuel.face.line"].sudo().search_count([
            ("origin_ticket_transfer_line_id", "=", line.id),
        ]), 1)

    def test_transfer_tickets_rejects_same_key_with_different_payload(self):
        (
            controller, _source_user, _source_login, _recipient_user, recipient_login,
            _session, _carnet_type, _purchase, face_line, source_wallet, _dest_wallet,
        ) = self._controller_with_ticket_transfer_fixture(25005)
        key = "ticket-transfer-conflict-key-i2"
        first = self._call_transfer_tickets(controller, self._payload(recipient_login, face_line, key=key, note="A"))
        self.assertNotIn("idempotency_conflict", repr(first))
        second = self._call_transfer_tickets(controller, self._payload(recipient_login, face_line, key=key, note="B"))
        self._assert_error_contains(second, "idempotency_conflict")
        transfers = self._transfer_by_key(source_wallet, key)
        self.assertEqual(len(transfers), 1)

    def test_transfer_tickets_accepts_missing_optional_note(self):
        (
            controller, _source_user, _source_login, _recipient_user, recipient_login,
            _session, _carnet_type, _purchase, face_line, source_wallet, _dest_wallet,
        ) = self._controller_with_ticket_transfer_fixture(25008)
        key = "ticket-transfer-no-note-i2"
        response = self._call_transfer_tickets(
            controller,
            self._payload(recipient_login, face_line, key=key, note=None, qty=2),
        )

        self.assertIn("True", repr(response))
        transfer = self._transfer_by_key(source_wallet, key)
        self.assertEqual(len(transfer), 1)
        self.assertEqual(transfer.state, "confirmed")
        self.assertFalse(transfer.note)

    def test_transfer_tickets_requires_trusted_device(self):
        (
            controller, _source_user, _source_login, _recipient_user, recipient_login,
            _session, _carnet_type, _purchase, face_line, source_wallet, _dest_wallet,
        ) = self._controller_with_ticket_transfer_fixture(25006, trusted=False)
        key = "ticket-transfer-untrusted-device-key-i2"
        response = self._call_transfer_tickets(controller, self._payload(recipient_login, face_line, key=key))
        self._assert_error_contains(response, "Device mobile en attente de validation")
        self.assertFalse(self._transfer_by_key(source_wallet, key))

    def test_transfer_tickets_rejects_carnet_qty_contract(self):
        (
            controller, _source_user, _source_login, _recipient_user, recipient_login,
            _session, _carnet_type, _purchase, face_line, source_wallet, _dest_wallet,
        ) = self._controller_with_ticket_transfer_fixture(25007)
        key = "ticket-transfer-carnet-qty-refused-i2"
        payload = self._payload(recipient_login, face_line, key=key)
        payload["lines"] = [{"face_line_id": face_line.id, "carnet_qty": 1}]
        self._assert_error_contains(self._call_transfer_tickets(controller, payload), "qty_tickets")
        self.assertFalse(self._transfer_by_key(source_wallet, key))

    def test_ticket_transfer_mobile_confirmation_requires_internal_helper(self):
        (
            _controller, source_user, _source_login, _recipient_user,
            _recipient_login, session, _carnet_type, _purchase, face_line,
            source_wallet, dest_wallet,
        ) = self._controller_with_ticket_transfer_fixture(25008)

        transfer = self.env[
            'acpec.fuel.ticket.transfer'
        ]._create_internal({
            'source_wallet_id': source_wallet.id,
            'dest_wallet_id': dest_wallet.id,
            'company_id': self.company.id,
            'idempotency_key': 'ticket-transfer-mobile-helper-i2',
            'request_hash': 'ticket-transfer-mobile-helper-hash-i2',
            'line_ids': [(0, 0, {
                'source_face_line_id': face_line.id,
                'qty_faces': 1,
            })],
        })

        with self.assertRaises(AccessError):
            transfer.action_confirm_mobile(
                actor_user=source_user,
                mobile_session=session,
            )

        transfer._confirm_mobile_internal(
            actor_user=source_user,
            mobile_session=session,
        )
        transfer.invalidate_recordset([
            'state',
            'confirmed_by',
            'mobile_session_id',
            'device_uid',
        ])
        self.assertEqual(transfer.state, 'confirmed')
        self.assertEqual(transfer.confirmed_by, source_user)
        self.assertEqual(transfer.mobile_session_id, session)
        self.assertEqual(transfer.device_uid, session.device_uid)
