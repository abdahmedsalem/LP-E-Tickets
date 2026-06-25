# -*- coding: utf-8 -*-
import base64
from types import SimpleNamespace
from unittest.mock import patch

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
            "login": login,
            "email": login,
            "active": True,
            "company_id": self.company.id,
            "company_ids": [(6, 0, [self.company.id])],
            "mobile_only": True,
            "mobile_state": "approved",
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
        purchase = self.env["acpec.fuel.purchase"].sudo().create({
            "partner_id": client_user.partner_id.id,
            "company_id": self.company.id,
            "payment_reference": "PAY-STATION-QR-24F",
        })
        self.env["acpec.fuel.purchase.line"].sudo().create({
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
        purchase.write({"proof_attachment_ids": [(4, attachment.id)]})
        purchase.action_submit()
        purchase.action_approve()
        purchase._create_face_lines_after_approval()

        wallet = self.env["acpec.fuel.wallet"].sudo().get_or_create(client_user.partner_id, self.company)
        return carnet_type, purchase, wallet

    def _issue_client_qr(self, client_user, key_suffix):
        carnet_type, purchase, wallet = self._create_available_stock(client_user)
        qr = self.env["acpec.fuel.qr"].sudo().issue_from_available(
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
        wallet = self.env['acpec.fuel.wallet'].sudo().create({
            'partner_id': partner.id,
            'company_id': other_company.id,
        })
        qr = self.env['acpec.fuel.qr'].sudo().create({
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
        self.assertNotIn("qr_id", repr(response))
        self.assertNotIn(foreign_qr.public_code, repr(response))
        self.assertNotIn("partner_name", repr(response))
        self.assertNotIn(str(foreign_qr.company_id.id), repr(response))

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
        foreign_tx = self.env['acpec.fuel.transaction'].sudo().create({
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
        controller, _station_user, station, _session, _client_user, qr = self._controller_with_consumable_qr(
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
        self.assertIn(str(tx.id), repr(response))
        self.assertEqual(tx.station_id.id, station.id)

        qr.invalidate_recordset(["state", "consumed_station_id"])
        self.assertEqual(qr.state, "consumed")
        self.assertEqual(qr.consumed_station_id.id, station.id)

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
