# -*- coding: utf-8 -*-
from datetime import timedelta
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

from odoo import fields
from odoo.exceptions import AccessError, UserError, ValidationError
from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_fueltoken_api.controllers import api_station as api_station_module
from odoo.addons.acpec_fueltoken_api.controllers.api_station import AcpecFuelTokenStationApi


@tagged("post_install", "-at_install")
class TestStationQrUseRuntimePolicy(TransactionCase):
    # Runtime policy coverage for /station/qr/use.
    # The fixture builds a real client QR, a real station user/session,
    # a real acpec.fuel.station record, then calls the real station controller.

    QR_QTY = 2

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.company = cls.env.company

    def _create_unique_carnet_type(self):
        carnet_model = self.env["acpec.fuel.carnet.type"].sudo()
        face_count = 10
        for face_value in range(950001, 950501):
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
        self.fail("Impossible de créer un type de carnet isolé pour le test station QR.")

    def _group_ids(self, xmlids):
        ids = []
        for xmlid in xmlids:
            group = self.env.ref(xmlid, raise_if_not_found=False)
            if group:
                ids.append(group.id)
        return ids

    def _mobile_client_group_ids(self):
        return self._group_ids([
            "base.group_portal",
            "acpec_mobile_auth.group_mobile_auth_user",
            "acpec_fueltoken_base.group_fuel_user",
        ])

    def _station_group_ids(self):
        return self._group_ids([
            "base.group_portal",
            "acpec_mobile_auth.group_mobile_auth_user",
            "acpec_fueltoken_base.group_fuel_station",
        ])

    def _create_mobile_user(self, login, group_ids):
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
            "group_ids": [(6, 0, group_ids)],
        })
        user.set_mobile_pin("1234")
        return user

    def _create_client_user(self, login):
        return self._create_mobile_user(login, self._mobile_client_group_ids())

    def _create_station_user(self, login):
        return self._create_mobile_user(login, self._station_group_ids())

    def _create_station_record(self, station_user, suffix):
        Station = self.env["acpec.fuel.station"].sudo()
        fields_map = Station._fields
        vals = {
            "name": "Station runtime 24F %s" % suffix,
            "company_id": self.company.id,
        }
        if "code" in fields_map:
            vals["code"] = "ST24F%s" % suffix
        if "active" in fields_map:
            vals["active"] = True
        if "user_id" in fields_map:
            vals["user_id"] = station_user.id
        if "station_user_id" in fields_map:
            vals["station_user_id"] = station_user.id
        if "partner_id" in fields_map:
            vals["partner_id"] = station_user.partner_id.id
        return Station.create(vals)

    def _station_controller(self, login, trusted=True):
        station_user = self._create_station_user(login)
        station = self._create_station_record(
            station_user,
            login.replace("@", "-").replace(".", "-"),
        )
        token_data = self.env["acpec.mobile.session"].sudo().create_for_user(station_user, {
            "device_uid": "dev-station-%s" % login.replace("@", "-").replace(".", "-"),
            "platform": "android",
        })
        session = token_data["session"]
        if trusted:
            session.action_trust_device()

        controller = AcpecFuelTokenStationApi()
        controller._test_env = self.env
        controller._get_mobile_session = lambda required=True: session
        return controller, station_user, station, session

    def _create_available_stock(self, client_user):
        carnet_type = self._create_unique_carnet_type()
        purchase = self.env["acpec.fuel.purchase"]._create_internal({
            "partner_id": client_user.partner_id.id,
            "company_id": self.company.id,
            "payment_reference": "PAY-STATION-QR-24F",
        })
        self.env["acpec.fuel.purchase.line"]._create_internal({
            "purchase_id": purchase.id,
            "carnet_type_id": carnet_type.id,
            "carnet_qty": 1,
        })
        attachment = self.env["ir.attachment"].sudo().create({
            "name": "preuve.pdf",
            "datas": base64.b64encode(b"%PDF-1.4\npreuve station qr use 24F\n").decode("ascii"),
            "mimetype": "application/pdf",
            "res_model": purchase._name,
            "res_id": purchase.id,
            "type": "binary",
        })
        purchase._write_proof_internal({"proof_attachment_ids": [(4, attachment.id)]})
        purchase.action_submit()
        purchase.action_approve()
        purchase._create_face_lines_after_approval()

        wallet = self.env["acpec.fuel.wallet"].sudo().get_or_create(client_user.partner_id, self.company)
        return carnet_type, purchase, wallet

    def _issue_client_qr(self, client_user, key_suffix):
        carnet_type, purchase, wallet = self._create_available_stock(client_user)
        qr = self.env["acpec.fuel.qr"]._issue_from_available_internal(
            client_user,
            wallet,
            [{"carnet_type_id": carnet_type.id, "qty": self.QR_QTY}],
            idempotency_key="source-station-qr-%s" % key_suffix,
            request_hash="source-station-qr-hash-%s" % key_suffix,
        )
        self.assertEqual(qr.state, "active")
        self.assertEqual(qr.face_qty_total, self.QR_QTY)
        self.assertTrue(qr.line_ids)
        return carnet_type, purchase, wallet, qr


    def _create_foreign_company_qr(self, suffix):
        other_company = self.env['res.company'].sudo().create({
            'name': 'Foreign FuelToken QR %s' % suffix,
            'acpec_fueltoken_enabled': False,
        })
        partner = self.env['res.partner'].sudo().create({
            'name': 'Foreign QR Partner %s' % suffix,
        })
        wallet = self.env['acpec.fuel.wallet']._create_internal({
            'partner_id': partner.id,
            'company_id': other_company.id,
        })
        qr = self.env['acpec.fuel.qr']._create_internal({
            'wallet_id': wallet.id,
        })
        self.assertNotEqual(qr.company_id, self.company)
        return other_company, wallet, qr

    def _controller_with_consumable_qr(self, suffix, trusted=True):
        client_user = self._create_client_user("client-station-qr-%s@example.com" % suffix)
        _carnet_type, _purchase, _wallet, qr = self._issue_client_qr(client_user, suffix)
        controller, station_user, station, session = self._station_controller(
            "station-qr-use-%s@example.com" % suffix,
            trusted=trusted,
        )
        return controller, station_user, station, session, client_user, qr

    def _payload(self, qr, key="station-qr-use-runtime-key", **extra):
        payload = {
            "public_code": qr.public_code,
            "action_code": "1234",
            "idempotency_key": key,
        }
        payload.update(extra)
        return payload

    def _payload_numeric(self, qr, key="station-qr-use-numeric-key", **extra):
        payload = {
            "qr_numeric_code": qr._qr_numeric_code_display(),
            "action_code": "1234",
            "idempotency_key": key,
        }
        payload.update(extra)
        return payload

    def _call_check_qr(self, controller, payload):
        fake_request = SimpleNamespace(env=self.env)
        with patch.object(api_station_module, "request", fake_request):
            return controller.check_qr(**payload)

    def _call_use_qr(self, controller, payload):
        fake_request = SimpleNamespace(env=self.env)
        with patch.object(api_station_module, "request", fake_request):
            return controller.use_qr(**payload)

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

    def _tx_by_key(self, qr, key):
        return self.env["acpec.fuel.transaction"].sudo().search([
            ("transaction_type", "=", "consommation_station"),
            ("qr_id", "=", qr.id),
            ("idempotency_key", "=", key),
        ])

    def test_station_qr_check_accepts_qr_numeric_code(self):
        controller, _station_user, _station, _session, _client_user, qr = self._controller_with_consumable_qr(
            "numeric-check-37a",
        )

        response = self._call_check_qr(controller, {
            "qr_numeric_code": qr._qr_numeric_code_display(),
        })

        self.assertIn(str(qr.id), repr(response))
        self.assertIn("can_consume", repr(response))
        self.assertIn("True", repr(response))


    def test_station_qr_check_rejects_foreign_company_without_payload(self):
        controller, _station_user, _station, _session, _client_user, _qr = self._controller_with_consumable_qr(
            "foreign-check-43e2",
        )
        _other_company, _foreign_wallet, foreign_qr = self._create_foreign_company_qr("check-43e2")

        response = self._call_check_qr(controller, {
            "public_code": foreign_qr.public_code,
        })

        self._assert_error_contains(response, "QR introuvable")

        self.assertIsInstance(response, dict)
        self.assertFalse(response.get("success"))
        self.assertFalse(response.get("ok"))
        self.assertNotIn("data", response)

        error = response.get("error", {}) if isinstance(response, dict) else {}
        self.assertIsInstance(error, dict)
        self.assertEqual(error.get("code"), "QR_NOT_USABLE")
        self.assertEqual(error.get("message"), "QR introuvable ou non utilisable.")
        self.assertTrue(str(error.get("reference") or "").startswith("SEC-"))

        forbidden_payload_keys = {
            "qr_id",
            "qr_public_code",
            "public_code",
            "qr_numeric_code",
            "partner_id",
            "partner_name",
            "company_id",
            "company_name",
            "wallet_id",
            "amount_total",
            "face_qty_total",
            "state",
            "can_consume",
            "reason",
            "debug_reason",
        }
        self.assertFalse(forbidden_payload_keys.intersection(response.keys()))
        self.assertFalse(forbidden_payload_keys.intersection(error.keys()))
        self.assertNotIn(foreign_qr.public_code, repr(response))

    def test_station_qr_use_rejects_foreign_company_before_consumption(self):
        controller, _station_user, _station, _session, _client_user, _qr = self._controller_with_consumable_qr(
            "foreign-use-43e2",
        )
        _other_company, _foreign_wallet, foreign_qr = self._create_foreign_company_qr("use-43e2")
        key = "station-qr-foreign-company-use-43e2"

        response = self._call_use_qr(
            controller,
            self._payload(foreign_qr, key=key),
        )

        self._assert_error_contains(response, "QR introuvable")
        foreign_qr.invalidate_recordset(["state"])
        self.assertEqual(foreign_qr.state, "active")
        self.assertFalse(self._tx_by_key(foreign_qr, key))

    def test_station_transactions_are_limited_to_fueltoken_company(self):
        controller, _station_user, station, _session, _client_user, _qr = self._controller_with_consumable_qr(
            "foreign-tx-43e2",
        )
        other_company = self.env['res.company'].sudo().create({
            'name': 'Foreign station tx 43E2',
            'acpec_fueltoken_enabled': False,
        })
        foreign_tx = self.env['acpec.fuel.transaction'].sudo().with_context(allow_fuel_transaction_create=True).create({
            'transaction_type': 'consommation_station',
            'company_id': other_company.id,
            'station_id': station.id,
        })

        response = self._call_check_qr(controller, {"public_code": _qr.public_code})
        self.assertIn("True", repr(response))

        fake_request = SimpleNamespace(env=self.env)
        with patch.object(api_station_module, "request", fake_request):
            tx_response = controller.station_transactions()

        self.assertNotIn(str(foreign_tx.id), repr(tx_response))

    def test_station_qr_use_accepts_qr_numeric_code(self):
        controller, station_user, station, _session, client_user, qr = self._controller_with_consumable_qr(
            "numeric-use-37a",
        )
        key = "station-qr-numeric-use-37a"

        response = self._call_use_qr(
            controller,
            self._payload_numeric(qr, key=key),
        )

        txs = self._tx_by_key(qr, key)
        self.assertEqual(len(txs), 1)
        tx = txs
        response_data = self._response_data(response)
        self.assertIn(str(tx.id), repr(response))
        self.assertEqual(response_data["transaction_sign"], "no_effect")
        self.assertEqual(response_data["transaction_effect"], "no_effect")
        self.assertEqual(
            response_data["transaction_sign"],
            response_data["transaction_effect"],
        )
        self.assertEqual(response_data["signed_amount"], 0.0)
        self.assertEqual(tx.station_id.id, station.id)

        qr.invalidate_recordset([
            "state",
            "consumed_station_id",
            "consumed_user_id",
            "consumed_partner_id",
        ])
        tx.invalidate_recordset([
            "actor_user_id",
            "actor_partner_id",
            "counterparty_partner_id",
            "counterparty_user_id",
        ])
        self.assertEqual(qr.state, "consumed")
        self.assertEqual(qr.consumed_station_id.id, station.id)
        self.assertEqual(qr.consumed_user_id.id, station_user.id)
        self.assertEqual(qr.consumed_partner_id.id, station_user.partner_id.id)
        self.assertEqual(tx.actor_user_id.id, station_user.id)
        self.assertEqual(tx.actor_partner_id.id, station_user.partner_id.id)
        self.assertEqual(tx.counterparty_partner_id.id, client_user.partner_id.id)
        self.assertEqual(tx.counterparty_user_id.id, client_user.id)

    def test_station_qr_rejects_mixed_public_and_numeric_code(self):
        controller, _station_user, _station, _session, _client_user, qr = self._controller_with_consumable_qr(
            "numeric-mixed-37a",
        )
        payload = self._payload_numeric(qr, key="station-qr-numeric-mixed-37a")
        payload["public_code"] = qr.public_code

        response = self._call_use_qr(controller, payload)

        self._assert_error_contains(response, "QR graphique")
        self.assertFalse(self._tx_by_key(qr, "station-qr-numeric-mixed-37a"))

    def test_station_qr_use_requires_action_code_only(self):
        controller, _station_user, _station, _session, _client_user, qr = self._controller_with_consumable_qr(
            "action-code-24f",
        )

        missing = self._payload(qr, key="station-qr-missing-action-code")
        missing.pop("action_code")
        self._assert_error_contains(
            self._call_use_qr(controller, missing),
            "action_code",
        )
        self.assertFalse(self._tx_by_key(qr, "station-qr-missing-action-code"))

        for alias in ("action_pin", "pin", "secret_code"):
            key = "station-qr-alias-%s" % alias
            payload = self._payload(qr, key=key)
            payload.pop("action_code")
            payload[alias] = "1234"
            self._assert_error_contains(
                self._call_use_qr(controller, payload),
                "action_code",
            )
            self.assertFalse(self._tx_by_key(qr, key))

    def test_station_qr_use_requires_idempotency_key(self):
        controller, _station_user, _station, _session, _client_user, qr = self._controller_with_consumable_qr(
            "idempotency-required-24f",
        )

        payload = self._payload(qr, key="station-qr-will-be-removed")
        payload.pop("idempotency_key")
        self._assert_error_contains(
            self._call_use_qr(controller, payload),
            "idempotency_key",
        )
        self.assertFalse(self._tx_by_key(qr, "station-qr-will-be-removed"))

    def test_station_qr_use_replays_same_payload_for_same_idempotency_key(self):
        controller, _station_user, station, _session, _client_user, qr = self._controller_with_consumable_qr(
            "replay-24f",
        )
        key = "station-qr-replay-key-24f"
        payload = self._payload(qr, key=key)

        first_response = self._call_use_qr(controller, dict(payload))
        second_response = self._call_use_qr(controller, dict(payload))

        txs = self._tx_by_key(qr, key)
        self.assertEqual(len(txs), 1)
        tx = txs
        self.assertIn(str(tx.id), repr(first_response))
        self.assertIn(str(tx.id), repr(second_response))
        self.assertEqual(tx.station_id.id, station.id)
        self.assertTrue(tx.request_hash)

        qr.invalidate_recordset(["state", "consumed_station_id"])
        self.assertEqual(qr.state, "consumed")
        self.assertEqual(qr.consumed_station_id.id, station.id)

    def test_station_qr_use_rejects_same_key_with_different_payload(self):
        controller, _station_user, _station, _session, _client_user, qr = self._controller_with_consumable_qr(
            "conflict-24f",
        )
        key = "station-qr-conflict-key-24f"

        first = self._call_use_qr(
            controller,
            self._payload(qr, key=key, pump_no="A"),
        )
        self.assertNotIn("idempotency_conflict", repr(first))

        second = self._call_use_qr(
            controller,
            self._payload(qr, key=key, pump_no="B"),
        )
        self._assert_error_contains(second, "idempotency_conflict")

        txs = self._tx_by_key(qr, key)
        self.assertEqual(len(txs), 1)

    def test_station_qr_use_requires_trusted_device(self):
        controller, _station_user, _station, _session, _client_user, qr = self._controller_with_consumable_qr(
            "untrusted-device-24f",
            trusted=False,
        )
        key = "station-qr-untrusted-device-key-24f"

        response = self._call_use_qr(
            controller,
            self._payload(qr, key=key),
        )
        self._assert_error_contains(response, "Device mobile en attente de validation")
        self.assertFalse(self._tx_by_key(qr, key))

    def _create_backoffice_manager_user(self, login):
        user_model = self.env["res.users"].sudo().with_context(
            acpec_mobile_allow_password_write=True,
            no_reset_password=True,
        )
        return user_model.create({
            "name": login,
            "login": login,
            "email": login,
            "active": True,
            "company_id": self.company.id,
            "company_ids": [(6, 0, [self.company.id])],
            "acpec_mobile_only": False,
            "group_ids": [(6, 0, self._group_ids([
                "base.group_user",
                "acpec_fueltoken_base.group_fuel_manager",
            ]))],
        })

    def _call_station_transactions(self, controller, payload=None):
        fake_request = SimpleNamespace(env=self.env)
        with patch.object(api_station_module, "request", fake_request):
            return controller.station_transactions(**(payload or {}))

    def _response_data(self, response):
        self.assertIsInstance(response, dict)
        data = response.get("data")
        return data if isinstance(data, dict) else response

    def _station_controller_for_existing_station_user(self, station_user, station, suffix, trusted=True):
        token_data = self.env["acpec.mobile.session"].sudo().create_for_user(station_user, {
            "device_uid": "dev-station-existing-%s" % suffix,
            "platform": "android",
        })
        session = token_data["session"]
        if trusted:
            session.action_trust_device()

        controller = AcpecFuelTokenStationApi()
        controller._test_env = self.env
        controller._get_mobile_session = lambda required=True: session
        self.env["acpec.fuel.station.agent"].sudo().create({
            "station_id": station.id,
            "user_id": station_user.id,
            "active": True,
            "is_primary": False,
        })
        return controller, session

    def test_patch43m6_station_agent_sees_only_own_consumptions(self):
        responsible_controller, responsible_user, station, _session, _client_user, qr1 = self._controller_with_consumable_qr(
            "m6-agent-scope-responsible",
        )
        ordinary_user = self._create_station_user("station-qr-use-m6-agent@example.com")
        ordinary_controller, _ordinary_session = self._station_controller_for_existing_station_user(
            ordinary_user,
            station,
            "m6-agent",
        )

        client_user2 = self._create_client_user("client-station-qr-m6-agent@example.com")
        _carnet_type2, _purchase2, _wallet2, qr2 = self._issue_client_qr(client_user2, "m6-agent-scope-ordinary")

        key1 = "station-qr-m6-agent-scope-responsible"
        key2 = "station-qr-m6-agent-scope-ordinary"
        self._call_use_qr(responsible_controller, self._payload(qr1, key=key1))
        self._call_use_qr(ordinary_controller, self._payload(qr2, key=key2))

        tx1 = self._tx_by_key(qr1, key1)
        tx2 = self._tx_by_key(qr2, key2)
        self.assertEqual(tx1.actor_partner_id.id, responsible_user.partner_id.id)
        self.assertEqual(tx2.actor_partner_id.id, ordinary_user.partner_id.id)

        # Patch43M7: actor is audit/context, not the station-agent visibility key.
        # If a future manager/backend actor differs from the QR consumer, ordinary
        # station visibility must still be driven by qr.consumed_partner_id/user.
        tx1.with_context(allow_fuel_transaction_update=True).write({
            "actor_partner_id": ordinary_user.partner_id.id,
        })
        tx1.invalidate_recordset(["actor_partner_id"])
        self.assertEqual(tx1.actor_partner_id.id, ordinary_user.partner_id.id)
        self.assertEqual(tx1.qr_id.consumed_partner_id.id, responsible_user.partner_id.id)

        responsible_data = self._response_data(self._call_station_transactions(
            responsible_controller,
            {"regularization_state": "all", "limit": 100},
        ))
        responsible_ids = {item["id"] for item in responsible_data.get("items", [])}
        self.assertIn(tx1.id, responsible_ids)
        self.assertIn(tx2.id, responsible_ids)

        ordinary_data = self._response_data(self._call_station_transactions(
            ordinary_controller,
            {"regularization_state": "all", "limit": 100},
        ))
        ordinary_ids = {item["id"] for item in ordinary_data.get("items", [])}
        self.assertNotIn(tx1.id, ordinary_ids)
        self.assertIn(tx2.id, ordinary_ids)

    def test_patch43m6_station_transactions_limit_is_capped_to_100(self):
        controller, station_user, station, _session, _client_user, _qr = self._controller_with_consumable_qr(
            "m6-limit-cap",
        )
        Tx = self.env["acpec.fuel.transaction"].sudo().with_context(allow_fuel_transaction_create=True)
        for index in range(105):
            Tx.create({
                "transaction_type": "consommation_station",
                "company_id": self.company.id,
                "station_id": station.id,
                "actor_partner_id": station_user.partner_id.id,
                "regularization_state": "pending",
                "amount_total": index + 1,
                "qty_total": 1,
            })

        data = self._response_data(self._call_station_transactions(controller, {
            "regularization_state": "all",
            "limit": 999,
        }))
        self.assertEqual(data.get("limit"), 100)
        self.assertEqual(len(data.get("items", [])), 100)

    def test_patch43m6_station_transactions_rejects_date_range_over_365_days(self):
        controller, _station_user, _station, _session, _client_user, _qr = self._controller_with_consumable_qr(
            "m6-date-range",
        )

        response = self._call_station_transactions(controller, {
            "regularization_state": "all",
            "date_from": "2024-01-01 00:00:00",
            "date_to": "2026-01-02 00:00:00",
            "limit": 20,
        })

        self.assertFalse(response.get("success"))
        self.assertIn("365", repr(response))

    def test_patch43m6_station_transactions_rejects_date_to_without_date_from(self):
        controller, _station_user, _station, _session, _client_user, _qr = self._controller_with_consumable_qr(
            "m6-date-to-alone",
        )

        response = self._call_station_transactions(controller, {
            "regularization_state": "all",
            "date_to": "2026-01-02 00:00:00",
            "limit": 20,
        })

        self.assertFalse(response.get("success"))
        self.assertIn("date_from", repr(response))

    def test_patch43m6_station_transactions_payload_has_no_manual_qr_secret(self):
        controller, _station_user, _station, _session, _client_user, qr = self._controller_with_consumable_qr(
            "m6-no-secret",
        )
        key = "station-qr-m6-no-secret"
        self._call_use_qr(controller, self._payload_numeric(qr, key=key))

        response = self._call_station_transactions(controller, {
            "regularization_state": "all",
            "limit": 20,
        })
        data = self._response_data(response)
        items = [item for item in data.get("items", []) if item.get("qr_id") == qr.id]
        self.assertEqual(len(items), 1)
        item = items[0]
        self.assertEqual(item["transaction_sign"], "no_effect")
        self.assertEqual(item["transaction_effect"], "no_effect")
        self.assertEqual(item["transaction_sign"], item["transaction_effect"])
        self.assertEqual(item["signed_amount"], 0.0)

        self.assertNotIn("qr_numeric_code", repr(response))
        self.assertNotIn("qr_numeric_code_hash", repr(response))
        self.assertNotIn("qr_numeric_code_nonce", repr(response))
        self.assertNotIn(qr._qr_numeric_code_display(), repr(response))

    def test_station_consumption_transaction_starts_pending_regularization(self):
        controller, _station_user, _station, _session, _client_user, qr = self._controller_with_consumable_qr(
            "regularization-pending-h3b",
        )
        key = "station-qr-regularization-pending-h3b"

        response = self._call_use_qr(controller, self._payload(qr, key=key))
        tx = self._tx_by_key(qr, key)

        self.assertEqual(tx.regularization_state, "pending")
        self.assertFalse(tx.regularization_reference)
        self.assertEqual(qr.state, "consumed")
        self.assertIn("regularization_state", repr(response))
        self.assertIn("pending", repr(response))

        default_list = self._call_station_transactions(controller)
        self.assertIn(str(tx.id), repr(default_list))
        regularized_list = self._call_station_transactions(controller, {"regularization_state": "regularized"})
        self.assertNotIn(str(tx.id), repr(regularized_list))

    def test_station_transactions_filter_pending_regularized_all(self):
        controller, _station_user, _station, _session, _client_user, qr = self._controller_with_consumable_qr(
            "regularization-filter-h3b",
        )
        key = "station-qr-regularization-filter-h3b"
        self._call_use_qr(controller, self._payload(qr, key=key))
        tx = self._tx_by_key(qr, key)

        manager = self._create_backoffice_manager_user("bo-regularization-filter-h3b@example.com")
        tx.with_user(manager).action_mark_station_regularized("REG-H3B-001")
        tx.invalidate_recordset(["regularization_state", "regularization_reference", "regularization_date", "regularized_by_id"])

        self.assertEqual(tx.regularization_state, "regularized")
        self.assertEqual(tx.regularization_reference, "REG-H3B-001")
        self.assertEqual(tx.regularized_by_id.id, manager.id)
        self.assertEqual(qr.state, "consumed")

        pending_list = self._call_station_transactions(controller, {"regularization_state": "pending"})
        self.assertNotIn(str(tx.id), repr(pending_list))
        regularized_list = self._call_station_transactions(controller, {"regularization_state": "regularized"})
        self.assertIn(str(tx.id), repr(regularized_list))
        self.assertIn("REG-H3B-001", repr(regularized_list))
        all_list = self._call_station_transactions(controller, {"regularization_state": "all"})
        self.assertIn(str(tx.id), repr(all_list))

    def test_station_mobile_user_cannot_regularize_transaction(self):
        controller, station_user, _station, _session, _client_user, qr = self._controller_with_consumable_qr(
            "regularization-station-denied-h3b",
        )
        key = "station-qr-regularization-station-denied-h3b"
        self._call_use_qr(controller, self._payload(qr, key=key))
        tx = self._tx_by_key(qr, key)

        with self.assertRaises(AccessError):
            tx.with_user(station_user).action_mark_station_regularized("REG-H3B-DENIED")
        tx.invalidate_recordset(["regularization_state", "regularization_reference"])
        self.assertEqual(tx.regularization_state, "pending")
        self.assertFalse(tx.regularization_reference)

    def test_regularization_reference_is_not_unique(self):
        controller1, _station_user1, _station1, _session1, _client_user1, qr1 = self._controller_with_consumable_qr(
            "regularization-nonunique-a-h3b",
        )
        controller2, _station_user2, _station2, _session2, _client_user2, qr2 = self._controller_with_consumable_qr(
            "regularization-nonunique-b-h3b",
        )
        key1 = "station-qr-regularization-nonunique-a-h3b"
        key2 = "station-qr-regularization-nonunique-b-h3b"
        self._call_use_qr(controller1, self._payload(qr1, key=key1))
        self._call_use_qr(controller2, self._payload(qr2, key=key2))
        tx1 = self._tx_by_key(qr1, key1)
        tx2 = self._tx_by_key(qr2, key2)

        manager = self._create_backoffice_manager_user("bo-regularization-nonunique-h3b@example.com")
        (tx1 | tx2).with_user(manager).action_mark_station_regularized("REG-H3B-SAME")

        tx1.invalidate_recordset(["regularization_state", "regularization_reference"])
        tx2.invalidate_recordset(["regularization_state", "regularization_reference"])
        self.assertEqual(tx1.regularization_state, "regularized")
        self.assertEqual(tx2.regularization_state, "regularized")
        self.assertEqual(tx1.regularization_reference, "REG-H3B-SAME")
        self.assertEqual(tx2.regularization_reference, "REG-H3B-SAME")

    def _station_transactions_payload_m15(self, response):
        if not isinstance(response, dict):
            return {}
        for key in ('data', 'result', 'payload'):
            value = response.get(key)
            if isinstance(value, dict) and (
                'items' in value or 'totals' in value or 'count' in value
            ):
                return value
        return response

    def _create_station_total_tx_m15(
        self,
        station,
        amount,
        suffix,
        regularization_state='pending',
    ):
        company = (
            station.company_id
            if 'company_id' in station._fields and station.company_id
            else self.env.company
        )
        tx = self.env['acpec.fuel.transaction'].sudo().with_context(allow_fuel_transaction_create=True).create({
            'name': 'TX-M15-%s' % suffix,
            'transaction_type': 'consommation_station',
            'company_id': company.id,
            'station_id': station.id,
        })
        self.env['acpec.fuel.transaction.line'].sudo().with_context(allow_fuel_transaction_line_create=True).create({
            'transaction_id': tx.id,
            'face_value': amount,
            'qty': 1,
        })
        if regularization_state == 'regularized':
            tx.with_context(allow_fuel_transaction_regularization_update=True).write({
                'regularization_state': 'regularized',
                'regularization_reference': 'REG-M15-%s' % suffix,
                'regularization_date': fields.Datetime.now(),
                'regularized_by_id': self.env.user.id,
            })
        self.env.flush_all()
        tx.invalidate_recordset([
            'amount_total',
            'qty_total',
            'regularization_state',
            'regularization_reference',
        ])
        return tx

    def test_station_transactions_default_all_and_filtered_totals_m15(self):
        controller, _station_user, station, _session, _client_user, _qr = self._controller_with_consumable_qr(
            "totals-filtered-m15",
        )
        pending_tx = self._create_station_total_tx_m15(
            station,
            120.0,
            "PENDING",
            regularization_state='pending',
        )
        regularized_tx = self._create_station_total_tx_m15(
            station,
            80.0,
            "REGULARIZED",
            regularization_state='regularized',
        )

        default_response = self._call_station_transactions(controller, {
            'limit': 1,
            'offset': 0,
        })
        default_payload = self._station_transactions_payload_m15(default_response)
        default_totals = default_payload.get('totals') or {}

        self.assertEqual(default_payload.get('count'), 2)
        self.assertEqual(len(default_payload.get('items') or []), 1)
        self.assertEqual(default_totals.get('scope'), 'filtered')
        self.assertEqual(default_totals.get('regularization_state'), 'all')
        self.assertEqual(default_totals.get('qr_count'), 2)
        self.assertEqual(default_totals.get('transaction_count'), 2)
        self.assertAlmostEqual(
            default_totals.get('amount_total'),
            pending_tx.amount_total + regularized_tx.amount_total,
        )
        self.assertAlmostEqual(
            default_totals.get('qty_total'),
            pending_tx.qty_total + regularized_tx.qty_total,
        )

        pending_response = self._call_station_transactions(controller, {
            'regularization_state': 'pending',
            'limit': 1,
            'offset': 0,
        })
        pending_payload = self._station_transactions_payload_m15(pending_response)
        pending_totals = pending_payload.get('totals') or {}
        self.assertEqual(pending_payload.get('count'), 1)
        self.assertEqual(len(pending_payload.get('items') or []), 1)
        self.assertEqual(pending_totals.get('scope'), 'filtered')
        self.assertEqual(pending_totals.get('regularization_state'), 'pending')
        self.assertEqual(pending_totals.get('qr_count'), 1)
        self.assertAlmostEqual(pending_totals.get('amount_total'), pending_tx.amount_total)
        self.assertIn(str(pending_tx.id), repr(pending_response))
        self.assertNotIn(str(regularized_tx.id), repr(pending_response))

        regularized_response = self._call_station_transactions(controller, {
            'regularization_state': 'regularized',
            'limit': 1,
            'offset': 0,
        })
        regularized_payload = self._station_transactions_payload_m15(regularized_response)
        regularized_totals = regularized_payload.get('totals') or {}
        self.assertEqual(regularized_payload.get('count'), 1)
        self.assertEqual(len(regularized_payload.get('items') or []), 1)
        self.assertEqual(regularized_totals.get('scope'), 'filtered')
        self.assertEqual(regularized_totals.get('regularization_state'), 'regularized')
        self.assertEqual(regularized_totals.get('qr_count'), 1)
        self.assertAlmostEqual(
            regularized_totals.get('amount_total'),
            regularized_tx.amount_total,
        )
        regularized_items = regularized_response.get('data', {}).get('items', [])
        self.assertNotIn(pending_tx.id, [item.get('id') for item in regularized_items])
        self.assertIn(str(regularized_tx.id), repr(regularized_response))

    def test_station_transactions_totals_follow_date_and_regularization_m15(self):
        controller, _station_user, station, _session, _client_user, _qr = self._controller_with_consumable_qr(
            "totals-date-reg-m15",
        )
        old_tx = self._create_station_total_tx_m15(
            station,
            50.0,
            "OLD-DATE",
            regularization_state='pending',
        )
        current_pending_tx = self._create_station_total_tx_m15(
            station,
            70.0,
            "CURRENT-PENDING",
            regularization_state='pending',
        )
        current_regularized_tx = self._create_station_total_tx_m15(
            station,
            90.0,
            "CURRENT-REGULARIZED",
            regularization_state='regularized',
        )

        now = fields.Datetime.now()
        old_date = now - timedelta(days=10)
        current_date = now

        self.env.cr.execute(
            "UPDATE acpec_fuel_transaction SET create_date = %s WHERE id = %s",
            [fields.Datetime.to_string(old_date), old_tx.id],
        )
        self.env.cr.execute(
            "UPDATE acpec_fuel_transaction SET create_date = %s WHERE id = %s",
            [fields.Datetime.to_string(current_date), current_pending_tx.id],
        )
        self.env.cr.execute(
            "UPDATE acpec_fuel_transaction SET create_date = %s WHERE id = %s",
            [fields.Datetime.to_string(current_date), current_regularized_tx.id],
        )
        self.env['acpec.fuel.transaction'].invalidate_model(['create_date'])

        pending_response = self._call_station_transactions(controller, {
            'regularization_state': 'pending',
            'date_from': fields.Datetime.to_string(now - timedelta(days=1)),
            'date_to': fields.Datetime.to_string(now + timedelta(days=1)),
            'limit': 1,
            'offset': 0,
        })
        pending_payload = self._station_transactions_payload_m15(pending_response)
        pending_totals = pending_payload.get('totals') or {}

        self.assertEqual(pending_payload.get('count'), 1)
        self.assertEqual(len(pending_payload.get('items') or []), 1)
        self.assertEqual(pending_totals.get('regularization_state'), 'pending')
        self.assertEqual(pending_totals.get('qr_count'), 1)
        self.assertAlmostEqual(
            pending_totals.get('amount_total'),
            current_pending_tx.amount_total,
        )
        self.assertNotIn(str(old_tx.id), repr(pending_response))
        self.assertNotIn(str(current_regularized_tx.id), repr(pending_response))

        all_response = self._call_station_transactions(controller, {
            'regularization_state': 'all',
            'date_from': fields.Datetime.to_string(now - timedelta(days=1)),
            'date_to': fields.Datetime.to_string(now + timedelta(days=1)),
            'limit': 1,
            'offset': 0,
        })
        all_payload = self._station_transactions_payload_m15(all_response)
        all_totals = all_payload.get('totals') or {}

        self.assertEqual(all_payload.get('count'), 2)
        self.assertEqual(len(all_payload.get('items') or []), 1)
        self.assertEqual(all_totals.get('regularization_state'), 'all')
        self.assertEqual(all_totals.get('qr_count'), 2)
        self.assertAlmostEqual(
            all_totals.get('amount_total'),
            current_pending_tx.amount_total + current_regularized_tx.amount_total,
        )
        self.assertNotIn(str(old_tx.id), repr(all_response))
