# -*- coding: utf-8 -*-
import base64
from types import SimpleNamespace
from unittest.mock import patch

from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_fueltoken_api.controllers import api_admin as api_admin_module
from odoo.addons.acpec_fueltoken_api.controllers import api_mobile as api_mobile_module
from odoo.addons.acpec_fueltoken_api.controllers import api_station as api_station_module
from odoo.addons.acpec_fueltoken_api.controllers.api_admin import AcpecFuelTokenAdminApi
from odoo.addons.acpec_fueltoken_api.controllers.api_mobile import AcpecFuelTokenMobileApi
from odoo.addons.acpec_fueltoken_api.controllers.api_station import AcpecFuelTokenStationApi


def _acpec_test_mobile_phone(label):
    """Return a deterministic canonical 8-digit mobile phone for test labels."""
    value = 2166136261
    for char in str(label):
        value ^= ord(char)
        value = (value * 16777619) % 10000000
    return "3%07d" % value


@tagged("post_install", "-at_install")
class TestRoleBasedSmokeH3(TransactionCase):
    """Patch43H3: end-to-end smoke coverage for mobile role boundaries.

    H3 deliberately stays runtime-test-only.  It reuses the existing lightweight controller test pattern:
    controller._test_env + patched request.env.  It avoids changing any business code.
    """

    QR_QTY = 2

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.company = cls.env.company

    def _group_ids(self, xmlids):
        ids = []
        for xmlid in xmlids:
            group = self.env.ref(xmlid, raise_if_not_found=False)
            if group:
                ids.append(group.id)
        return ids

    def _client_group_ids(self):
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

    def _manager_group_ids(self):
        return self._group_ids([
            "base.group_portal",
            "acpec_mobile_auth.group_mobile_auth_user",
            "acpec_fueltoken_base.group_fuel_manager",
        ])

    def _create_mobile_user(self, label, group_ids):
        user_model = self.env["res.users"].sudo().with_context(
            acpec_mobile_allow_password_write=True,
            no_reset_password=True,
        )
        user = user_model.create({
            "name": label,
            "login": _acpec_test_mobile_phone(label),
            "mobile_phone": _acpec_test_mobile_phone(label),
            "email": label,
            "active": True,
            "company_id": self.company.id,
            "company_ids": [(6, 0, [self.company.id])],
            "acpec_mobile_only": True,
            "acpec_mobile_state": "approved",
            "password": user_model._acpec_mobile_unusable_password(),
            "group_ids": [(6, 0, group_ids)],
        })
        user.set_mobile_pin("1234")
        if user.partner_id:
            user.partner_id.sudo().write({
                "company_id": self.company.id,
            })
        return user

    def _create_client_user(self, label):
        return self._create_mobile_user(label, self._client_group_ids())

    def _create_station_user(self, label):
        return self._create_mobile_user(label, self._station_group_ids())

    def _create_manager_user(self, label):
        return self._create_mobile_user(label, self._manager_group_ids())

    def _create_session(self, user, device_uid, trusted=True):
        token_data = self.env["acpec.mobile.session"].sudo().create_for_user(user, {
            "device_uid": device_uid,
            "device_name": device_uid,
            "platform": "android",
        })
        session = token_data["session"]
        if trusted:
            session.sudo().action_trust_device()
        return session

    def _mobile_controller(self, session):
        controller = AcpecFuelTokenMobileApi()
        controller._test_env = self.env
        controller._get_mobile_session = lambda required=True: session
        return controller

    def _station_controller(self, session):
        controller = AcpecFuelTokenStationApi()
        controller._test_env = self.env
        controller._get_mobile_session = lambda required=True: session
        return controller

    def _admin_controller(self, session):
        controller = AcpecFuelTokenAdminApi()
        controller._test_env = self.env
        controller._get_mobile_session = lambda required=True: session
        return controller

    def _call_mobile(self, controller, method_name, payload=None):
        fake_request = SimpleNamespace(env=self.env)
        with patch.object(api_mobile_module, "request", fake_request):
            return getattr(controller, method_name)(**(payload or {}))

    def _call_station(self, controller, method_name, payload=None):
        fake_request = SimpleNamespace(env=self.env)
        with patch.object(api_station_module, "request", fake_request):
            return getattr(controller, method_name)(**(payload or {}))

    def _call_admin(self, controller, method_name, payload=None):
        fake_request = SimpleNamespace(env=self.env)
        with patch.object(api_admin_module, "request", fake_request):
            return getattr(controller, method_name)(**(payload or {}))

    def _assert_success(self, response):
        self.assertTrue(response.get("success"), repr(response))
        return response.get("data") or {}

    def _assert_refused(self, response):
        self.assertFalse(response.get("success"), repr(response))
        self.assertIn("error", response, repr(response))
        return response.get("error") or {}

    def _create_unique_carnet_type(self):
        carnet_model = self.env["acpec.fuel.carnet.type"].sudo()
        face_count = 10
        for face_value in range(990001, 990901):
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
        self.fail("Impossible de créer un type de carnet isolé pour le smoke H3.")

    def _create_available_stock(self, client_user, suffix):
        carnet_type = self._create_unique_carnet_type()
        purchase = self.env["acpec.fuel.purchase"].with_context(allow_fuel_purchase_create=True, allow_fuel_purchase_line_create=True).sudo().create({
            "partner_id": client_user.partner_id.id,
            "company_id": self.company.id,
            "payment_reference": "PAY-H3-%s" % suffix,
        })
        self.env["acpec.fuel.purchase.line"].with_context(allow_fuel_purchase_line_create=True).sudo().create({
            "purchase_id": purchase.id,
            "carnet_type_id": carnet_type.id,
            "carnet_qty": 1,
        })
        attachment = self.env["ir.attachment"].sudo().create({
            "name": "preuve-h3.pdf",
            "datas": base64.b64encode(b"%PDF-1.4\npreuve smoke h3\n").decode("ascii"),
            "mimetype": "application/pdf",
            "res_model": purchase._name,
            "res_id": purchase.id,
            "type": "binary",
        })
        purchase.with_context(allow_fuel_purchase_update=True).sudo().write({"proof_attachment_ids": [(4, attachment.id)]})
        purchase.action_submit()
        purchase.action_approve()
        purchase._create_face_lines_after_approval()

        face_line = self.env["acpec.fuel.face.line"].sudo().search([
            ("purchase_id", "=", purchase.id),
        ], limit=1)
        self.assertTrue(face_line)
        self.assertGreater(face_line.qty_available, 0)

        wallet = self.env["acpec.fuel.wallet"].sudo().get_or_create(client_user.partner_id, self.company)
        return carnet_type, purchase, wallet

    def _create_submitted_purchase(self, suffix):
        client_user = self._create_client_user("h3-purchase-client-%s@example.com" % suffix)
        self._create_session(
            client_user,
            "dev-h3-purchase-client-%s" % str(suffix).replace("@", "-").replace(".", "-"),
            trusted=True,
        )
        carnet_type = self._create_unique_carnet_type()
        purchase = self.env["acpec.fuel.purchase"].with_context(allow_fuel_purchase_create=True, allow_fuel_purchase_line_create=True).sudo().create({
            "partner_id": client_user.partner_id.id,
            "company_id": self.company.id,
            "payment_reference": "PAY-H3-SUBMITTED-%s" % suffix,
        })
        self.env["acpec.fuel.purchase.line"].with_context(allow_fuel_purchase_line_create=True).sudo().create({
            "purchase_id": purchase.id,
            "carnet_type_id": carnet_type.id,
            "carnet_qty": 1,
        })
        attachment = self.env["ir.attachment"].sudo().create({
            "name": "preuve-h3-submitted.pdf",
            "datas": base64.b64encode(b"%PDF-1.4\npreuve submitted smoke h3\n").decode("ascii"),
            "mimetype": "application/pdf",
            "res_model": purchase._name,
            "res_id": purchase.id,
            "type": "binary",
        })
        purchase.with_context(allow_fuel_purchase_update=True).sudo().write({"proof_attachment_ids": [(4, attachment.id)]})
        purchase.action_submit()
        purchase.invalidate_recordset(["state"])
        self.assertEqual(purchase.state, "submitted")
        return purchase

    def _issue_qr_direct(self, client_user, suffix):
        carnet_type, _purchase, wallet = self._create_available_stock(client_user, suffix)
        qr = self.env["acpec.fuel.qr"].sudo().issue_from_available(
            wallet,
            [{"carnet_type_id": carnet_type.id, "qty": self.QR_QTY}],
            idempotency_key="h3-direct-qr-%s" % suffix,
            request_hash="h3-direct-qr-hash-%s" % suffix,
        )
        qr._ensure_qr_numeric_code_hash()
        qr.invalidate_recordset(["qr_numeric_code_hash", "qr_numeric_code_nonce", "state"])
        self.assertEqual(qr.state, "active")
        self.assertTrue(qr._qr_numeric_code_display())
        return qr

    def _issue_qr_via_mobile_controller(self, client_user, client_session, suffix):
        carnet_type, _purchase, _wallet = self._create_available_stock(client_user, suffix)
        controller = self._mobile_controller(client_session)
        response = self._call_mobile(controller, "issue_qr", {
            "lines": [{
                "carnet_type_id": carnet_type.id,
                "qty": self.QR_QTY,
            }],
            "action_code": "1234",
            "idempotency_key": "h3-mobile-issue-%s" % suffix,
        })
        data = self._assert_success(response)
        qr = self.env["acpec.fuel.qr"].sudo().search([
            ("public_code", "=", data.get("public_code")),
        ], limit=1)
        self.assertTrue(qr)
        self.assertEqual(qr.state, "active")
        self.assertNotIn("qr_numeric_code", data)
        self.assertTrue(data.get("name"))
        self.assertTrue(data.get("public_code"))
        return qr

    def _create_station_record(self, station_user, suffix):
        Station = self.env["acpec.fuel.station"].sudo()
        fields_map = Station._fields
        vals = {
            "name": "Station smoke H3 %s" % suffix,
            "company_id": self.company.id,
        }
        if "code" in fields_map:
            base_code = ("STH3%s" % suffix.replace("-", "").replace(".", "")).upper()[:18]
            code = base_code
            for idx in range(100):
                if not Station.search([
                    ("company_id", "=", self.company.id),
                    ("code", "=", code),
                ], limit=1):
                    vals["code"] = code
                    break
                code = ("%s%02d" % (base_code[:16], idx))[:20]
            if "code" not in vals:
                self.fail("Impossible de créer un code station isolé pour le smoke H3.")
        if "active" in fields_map:
            vals["active"] = True
        if "user_id" in fields_map:
            vals["user_id"] = station_user.id
        if "station_user_id" in fields_map:
            vals["station_user_id"] = station_user.id
        if "partner_id" in fields_map:
            vals["partner_id"] = station_user.partner_id.id
        return Station.create(vals)

    def _station_role_fixture(self, suffix):
        station_user = self._create_station_user("h3-station-%s@example.com" % suffix)
        station = self._create_station_record(station_user, suffix)
        session = self._create_session(
            station_user,
            "dev-h3-station-%s" % suffix,
            trusted=True,
        )
        controller = self._station_controller(session)
        return controller, station_user, station, session

    def _tx_by_key(self, qr, key):
        return self.env["acpec.fuel.transaction"].sudo().search([
            ("transaction_type", "=", "consommation_station"),
            ("qr_id", "=", qr.id),
            ("idempotency_key", "=", key),
        ], limit=1)

    def _station_tx_by_key(self, key):
        return self.env["acpec.fuel.transaction"].sudo().search([
            ("transaction_type", "=", "consommation_station"),
            ("idempotency_key", "=", key),
        ], limit=1)

    def test_client_mobile_role_can_issue_qr_but_cannot_act_as_station_or_manager(self):
        client_user = self._create_client_user("h3-client-role@example.com")
        client_session = self._create_session(client_user, "dev-h3-client-role", trusted=True)
        mobile = self._mobile_controller(client_session)

        self._assert_success(self._call_mobile(mobile, "current_wallet"))
        qr = self._issue_qr_via_mobile_controller(client_user, client_session, "client-role")

        station_as_client = self._station_controller(client_session)
        use_key = "h3-client-must-not-use-station-qr"
        self._assert_refused(self._call_station(station_as_client, "use_qr", {
            "public_code": qr.public_code,
            "action_code": "1234",
            "idempotency_key": use_key,
        }))
        self.assertFalse(self._tx_by_key(qr, use_key))
        qr.invalidate_recordset(["state"])
        self.assertEqual(qr.state, "active")

        admin_as_client = self._admin_controller(client_session)
        purchase = self._create_submitted_purchase("client-role")
        self._assert_refused(self._call_admin(admin_as_client, "purchase_approve", {
            "purchase_id": purchase.id,
            "action_code": "1234",
            "idempotency_key": "h3-client-must-not-approve-purchase",
        }))
        purchase.invalidate_recordset(["state"])
        self.assertEqual(purchase.state, "submitted")

        target_user = self._create_client_user("h3-client-role-device-target@example.com")
        target_session = self._create_session(
            target_user,
            "dev-h3-client-role-device-target",
            trusted=False,
        )
        self._assert_refused(self._call_admin(admin_as_client, "device_approve_pending_trust", {
            "device_id": target_session.device_id.id,
            "action_code": "1234",
            "idempotency_key": "h3-client-must-not-approve-device",
        }))
        target_session.device_id.invalidate_recordset(["trust_state"])
        self.assertEqual(target_session.device_id.trust_state, "pending_trust")

    def test_station_mobile_role_can_check_use_and_list_but_cannot_act_as_client_or_manager(self):
        controller, _station_user, station, station_session = self._station_role_fixture("station-role")
        client_user = self._create_client_user("h3-station-role-client@example.com")
        qr = self._issue_qr_direct(client_user, "station-role")

        profile = self._assert_success(self._call_station(controller, "profile"))
        self.assertEqual(profile.get("station_id"), station.id)

        check_public = self._assert_success(self._call_station(controller, "check_qr", {
            "public_code": qr.public_code,
        }))
        self.assertEqual(check_public.get("public_code"), qr.public_code)

        check_numeric = self._assert_success(self._call_station(controller, "check_qr", {
            "qr_numeric_code": qr._qr_numeric_code_display(),
        }))
        self.assertEqual(check_numeric.get("public_code"), qr.public_code)

        use_key = "h3-station-use-numeric"
        used = self._assert_success(self._call_station(controller, "use_qr", {
            "qr_numeric_code": qr._qr_numeric_code_display(),
            "action_code": "1234",
            "idempotency_key": use_key,
        }))
        self.assertEqual(used.get("qr_public_code"), qr.public_code)
        self.assertTrue(self._tx_by_key(qr, use_key))

        transactions = self._assert_success(self._call_station(controller, "station_transactions"))
        self.assertEqual(transactions.get("station", {}).get("station_id"), station.id)

        mobile_as_station = self._mobile_controller(station_session)
        self._assert_refused(self._call_mobile(mobile_as_station, "issue_qr", {
            "lines": [{"carnet_type_id": self._create_unique_carnet_type().id, "qty": 1}],
            "action_code": "1234",
            "idempotency_key": "h3-station-must-not-issue-qr",
        }))
        self._assert_refused(self._call_mobile(mobile_as_station, "transfer_carnets", {
            "recipient_phone": "30000001",
            "lines": [{"face_line_id": 1, "carnet_qty": 1}],
            "action_code": "1234",
            "idempotency_key": "h3-station-must-not-transfer",
        }))

        admin_as_station = self._admin_controller(station_session)
        purchase = self._create_submitted_purchase("station-role")
        self._assert_refused(self._call_admin(admin_as_station, "purchase_approve", {
            "purchase_id": purchase.id,
            "action_code": "1234",
            "idempotency_key": "h3-station-must-not-approve-purchase",
        }))
        purchase.invalidate_recordset(["state"])
        self.assertEqual(purchase.state, "submitted")

        target_user = self._create_client_user("h3-station-role-device-target@example.com")
        target_session = self._create_session(
            target_user,
            "dev-h3-station-role-device-target",
            trusted=False,
        )
        self._assert_refused(self._call_admin(admin_as_station, "device_approve_pending_trust", {
            "device_id": target_session.device_id.id,
            "action_code": "1234",
            "idempotency_key": "h3-station-must-not-approve-device",
        }))
        target_session.device_id.invalidate_recordset(["trust_state"])
        self.assertEqual(target_session.device_id.trust_state, "pending_trust")

        human_qr = self._issue_qr_direct(
            self._create_client_user("h3-station-human-code-client@example.com"),
            "station-human-code",
        )
        human_key = "h3-station-must-not-use-human-code"
        self._assert_refused(self._call_station(controller, "use_qr", {
            "acpec_human_code": "M9228",
            "action_code": "1234",
            "idempotency_key": human_key,
        }))
        self.assertFalse(self._station_tx_by_key(human_key))
        human_qr.invalidate_recordset(["state"])
        self.assertEqual(human_qr.state, "active")

    def test_manager_mobile_role_can_validate_positive_items_but_cannot_act_as_client_station_or_full_bo(self):
        manager = self._create_manager_user("h3-manager-role@example.com")
        manager_session = self._create_session(manager, "dev-h3-manager-role", trusted=True)
        admin = self._admin_controller(manager_session)

        target_user = self._create_client_user("h3-manager-device-target@example.com")
        target_session = self._create_session(target_user, "dev-h3-manager-device-target", trusted=False)
        pending_devices = self._assert_success(self._call_admin(admin, "devices_pending_trust"))
        self.assertIn(target_session.device_id.stable_device_uid, repr(pending_devices))

        approved_device = self._assert_success(self._call_admin(admin, "device_approve_pending_trust", {
            "device_id": target_session.device_id.id,
            "action_code": "1234",
            "idempotency_key": "h3-manager-approve-device",
        }))
        self.assertEqual(approved_device.get("trust_state"), "trusted")
        target_session.device_id.invalidate_recordset(["trust_state", "trusted_by"])
        self.assertEqual(target_session.device_id.trust_state, "trusted")
        self.assertEqual(target_session.device_id.trusted_by.id, manager.id)

        self._assert_success(self._call_admin(admin, "stations_list"))

        purchase = self._create_submitted_purchase("manager-role")
        pending_purchases = self._assert_success(self._call_admin(admin, "purchases_pending"))
        self.assertIn(purchase.name, repr(pending_purchases))

        detail = self._assert_success(self._call_admin(admin, "purchase_detail", {
            "purchase_id": purchase.id,
        }))
        self.assertEqual(detail.get("id"), purchase.id)

        approved_purchase = self._assert_success(self._call_admin(admin, "purchase_approve", {
            "purchase_id": purchase.id,
            "action_code": "1234",
            "idempotency_key": "h3-manager-approve-purchase",
        }))
        self.assertEqual(approved_purchase.get("state"), "approved")
        purchase.invalidate_recordset(["state", "approved_by"])
        self.assertEqual(purchase.state, "approved")

        client_user = self._create_client_user("h3-manager-station-negative-client@example.com")
        qr = self._issue_qr_direct(client_user, "manager-station-negative")
        station_as_manager = self._station_controller(manager_session)
        station_key = "h3-manager-must-not-use-station-qr"
        self._assert_refused(self._call_station(station_as_manager, "use_qr", {
            "public_code": qr.public_code,
            "action_code": "1234",
            "idempotency_key": station_key,
        }))
        self.assertFalse(self._tx_by_key(qr, station_key))
        qr.invalidate_recordset(["state"])
        self.assertEqual(qr.state, "active")

        mobile_as_manager = self._mobile_controller(manager_session)
        self._assert_refused(self._call_mobile(mobile_as_manager, "issue_qr", {
            "lines": [{"carnet_type_id": self._create_unique_carnet_type().id, "qty": 1}],
            "action_code": "1234",
            "idempotency_key": "h3-manager-must-not-issue-qr",
        }))
        transfer_recipient = self._create_client_user("h3-manager-transfer-recipient@example.com")
        unrelated_face_line = self.env["acpec.fuel.face.line"].sudo().search([
            ("wallet_id.partner_id", "=", client_user.partner_id.id),
            ("qty_available", ">", 0),
        ], limit=1)
        self.assertTrue(unrelated_face_line)
        transfer_key = "h3-manager-must-not-transfer"
        self._assert_refused(self._call_mobile(mobile_as_manager, "transfer_carnets", {
            "recipient_phone": transfer_recipient.acpec_mobile_phone,
            "lines": [{"face_line_id": unrelated_face_line.id, "carnet_qty": 1}],
            "action_code": "1234",
            "idempotency_key": transfer_key,
        }))
        self.assertFalse(self.env["acpec.fuel.carnet.transfer"].sudo().search([
            ("idempotency_key", "=", transfer_key),
        ]))

        self._assert_refused(self._call_admin(admin, "station_create", {
            "action_code": "1234",
            "idempotency_key": "h3-manager-station-create-bo-only",
        }))
        self._assert_refused(self._call_admin(admin, "carnet_type_create", {
            "action_code": "1234",
            "idempotency_key": "h3-manager-carnet-type-create-bo-only",
        }))
