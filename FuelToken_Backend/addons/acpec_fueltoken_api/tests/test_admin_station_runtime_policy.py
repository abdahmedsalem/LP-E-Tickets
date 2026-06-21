# -*- coding: utf-8 -*-
from types import SimpleNamespace
from unittest.mock import patch

from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_fueltoken_api.controllers import api_admin as api_admin_module
from odoo.addons.acpec_fueltoken_api.controllers.api_admin import AcpecFuelTokenAdminApi


@tagged("post_install", "-at_install")
class TestAdminStationRuntimePolicy(TransactionCase):
    # Runtime policy coverage for admin station create/update/disable.
    # Station admin decisions require trusted manager device, action_code,
    # idempotency_key and request_hash conflict protection.

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

    def _manager_group_ids(self):
        return self._group_ids([
            "base.group_portal",
            "acpec_mobile_auth.group_mobile_auth_user",
            "acpec_fueltoken_base.group_fuel_manager",
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

    def _create_manager_user(self, login):
        return self._create_mobile_user(login, self._manager_group_ids())

    def _create_station_user(self, login):
        return self._create_mobile_user(login, self._station_group_ids())

    def _admin_controller(self, login, trusted=True):
        manager = self._create_manager_user(login)
        token_data = self.env["acpec.mobile.session"].sudo().create_for_user(manager, {
            "device_uid": "dev-admin-station-%s" % login.replace("@", "-").replace(".", "-"),
            "platform": "android",
        })
        session = token_data["session"]
        if trusted:
            session.action_trust_device()

        controller = AcpecFuelTokenAdminApi()
        controller._test_env = self.env
        controller._get_mobile_session = lambda required=True: session
        return controller, manager, session

    def _call_create(self, controller, payload):
        fake_request = SimpleNamespace(env=self.env)
        with patch.object(api_admin_module, "request", fake_request):
            return controller.station_create(**payload)

    def _call_update(self, controller, payload):
        fake_request = SimpleNamespace(env=self.env)
        with patch.object(api_admin_module, "request", fake_request):
            return controller.station_update(**payload)

    def _call_disable(self, controller, payload):
        fake_request = SimpleNamespace(env=self.env)
        with patch.object(api_admin_module, "request", fake_request):
            return controller.station_disable(**payload)

    def _assert_error_contains(self, response, expected):
        self.assertIn(expected, repr(response))
        self.assertIn("success", repr(response))
        self.assertIn("False", repr(response))

    def _create_payload(self, station_user, key="admin-station-create-key", **extra):
        payload = {
            "name": "Station runtime create 25B",
            "code": "ST25BCREATE",
            "user_id": station_user.id,
            "company_id": self.company.id,
            "active": True,
            "action_code": "1234",
            "idempotency_key": key,
        }
        payload.update(extra)
        return payload

    def _update_payload(self, station, key="admin-station-update-key", **extra):
        payload = {
            "station_id": station.id,
            "name": "Station runtime updated 25B",
            "code": "ST25BUPDATED",
            "action_code": "1234",
            "idempotency_key": key,
        }
        payload.update(extra)
        return payload

    def _disable_payload(self, station, key="admin-station-disable-key", **extra):
        payload = {
            "station_id": station.id,
            "action_code": "1234",
            "idempotency_key": key,
        }
        payload.update(extra)
        return payload

    def _station_by_create_key(self, key):
        return self.env["acpec.fuel.station"].sudo().search([
            ("create_idempotency_key", "=", key),
        ])

    def _create_station_direct(self, suffix):
        station_user = self._create_station_user("station-direct-%s@example.com" % suffix)
        return self.env["acpec.fuel.station"].sudo().create({
            "name": "Station direct %s" % suffix,
            "code": "ST25B%s" % suffix.upper().replace("-", "")[:12],
            "user_id": station_user.id,
            "company_id": self.company.id,
            "active": True,
        })

    def test_station_create_requires_action_code_only(self):
        controller, _manager, _session = self._admin_controller("admin-station-create-action-25b@example.com")
        station_user = self._create_station_user("station-create-action-25b@example.com")

        missing = self._create_payload(station_user, key="station-create-missing-action-25b")
        missing.pop("action_code")
        self._assert_error_contains(self._call_create(controller, missing), "action_code")
        self.assertFalse(self._station_by_create_key("station-create-missing-action-25b"))

        for alias in ("action_pin", "pin", "secret_code"):
            key = "station-create-alias-%s-25b" % alias
            payload = self._create_payload(station_user, key=key)
            payload.pop("action_code")
            payload[alias] = "1234"
            self._assert_error_contains(self._call_create(controller, payload), "action_code")
            self.assertFalse(self._station_by_create_key(key))

    def test_station_create_requires_idempotency_key(self):
        controller, _manager, _session = self._admin_controller("admin-station-create-idem-25b@example.com")
        station_user = self._create_station_user("station-create-idem-25b@example.com")

        payload = self._create_payload(station_user, key="station-create-will-be-removed-25b")
        payload.pop("idempotency_key")
        self._assert_error_contains(self._call_create(controller, payload), "idempotency_key")
        self.assertFalse(self._station_by_create_key("station-create-will-be-removed-25b"))

    def test_station_create_requires_trusted_manager_device(self):
        controller, _manager, _session = self._admin_controller(
            "admin-station-create-untrusted-25b@example.com",
            trusted=False,
        )
        station_user = self._create_station_user("station-create-untrusted-25b@example.com")
        key = "station-create-untrusted-25b"

        response = self._call_create(controller, self._create_payload(station_user, key=key))
        self._assert_error_contains(response, "Device mobile en attente de validation")
        self.assertFalse(self._station_by_create_key(key))

    def test_station_create_replays_same_payload_for_same_idempotency_key(self):
        controller, _manager, _session = self._admin_controller("admin-station-create-replay-25b@example.com")
        station_user = self._create_station_user("station-create-replay-25b@example.com")
        key = "station-create-replay-key-25b"
        payload = self._create_payload(station_user, key=key, name="Station replay 25B", code="ST25BREPLAY")

        first = self._call_create(controller, dict(payload))
        second = self._call_create(controller, dict(payload))
        self.assertIn("Station replay 25B", repr(first))
        self.assertIn("Station replay 25B", repr(second))

        stations = self._station_by_create_key(key)
        self.assertEqual(len(stations), 1)
        self.assertEqual(stations.name, "Station replay 25B")
        self.assertEqual(stations.user_id.id, station_user.id)
        self.assertTrue(stations.create_request_hash)

    def test_station_create_rejects_same_key_with_different_payload(self):
        controller, _manager, _session = self._admin_controller("admin-station-create-conflict-25b@example.com")
        station_user = self._create_station_user("station-create-conflict-25b@example.com")
        key = "station-create-conflict-key-25b"

        first = self._call_create(
            controller,
            self._create_payload(station_user, key=key, name="Station conflict A", code="ST25BCONFA"),
        )
        self.assertNotIn("idempotency_conflict", repr(first))

        second = self._call_create(
            controller,
            self._create_payload(station_user, key=key, name="Station conflict B", code="ST25BCONFB"),
        )
        self._assert_error_contains(second, "idempotency_conflict")
        self.assertEqual(len(self._station_by_create_key(key)), 1)

    def test_station_update_requires_idempotency_and_replay_conflict(self):
        controller, _manager, _session = self._admin_controller("admin-station-update-25b@example.com")
        station = self._create_station_direct("update-25b")
        key = "station-update-replay-key-25b"
        payload = self._update_payload(station, key=key, name="Station updated replay 25B")

        missing = dict(payload)
        missing.pop("idempotency_key")
        self._assert_error_contains(self._call_update(controller, missing), "idempotency_key")

        first = self._call_update(controller, dict(payload))
        second = self._call_update(controller, dict(payload))
        self.assertIn("Station updated replay 25B", repr(first))
        self.assertIn("Station updated replay 25B", repr(second))

        station.invalidate_recordset(["name", "update_idempotency_key", "update_request_hash"])
        self.assertEqual(station.name, "Station updated replay 25B")
        self.assertEqual(station.update_idempotency_key, key)
        self.assertTrue(station.update_request_hash)

        conflict = self._call_update(
            controller,
            self._update_payload(station, key=key, name="Station updated conflict 25B"),
        )
        self._assert_error_contains(conflict, "idempotency_conflict")
        station.invalidate_recordset(["name"])
        self.assertEqual(station.name, "Station updated replay 25B")

    def test_station_update_requires_action_code_and_trusted_device(self):
        station = self._create_station_direct("update-guard-25b")

        controller, _manager, _session = self._admin_controller("admin-station-update-action-25b@example.com")
        missing = self._update_payload(station, key="station-update-missing-action-25b")
        missing.pop("action_code")
        self._assert_error_contains(self._call_update(controller, missing), "action_code")

        for alias in ("action_pin", "pin", "secret_code"):
            payload = self._update_payload(station, key="station-update-alias-%s-25b" % alias)
            payload.pop("action_code")
            payload[alias] = "1234"
            self._assert_error_contains(self._call_update(controller, payload), "action_code")

        untrusted_controller, _manager2, _session2 = self._admin_controller(
            "admin-station-update-untrusted-25b@example.com",
            trusted=False,
        )
        response = self._call_update(
            untrusted_controller,
            self._update_payload(station, key="station-update-untrusted-25b"),
        )
        self._assert_error_contains(response, "Device mobile en attente de validation")

    def test_station_disable_requires_idempotency_and_replay_conflict(self):
        controller, _manager, _session = self._admin_controller("admin-station-disable-25b@example.com")
        station = self._create_station_direct("disable-25b")
        key = "station-disable-replay-key-25b"
        payload = self._disable_payload(station, key=key)

        missing = dict(payload)
        missing.pop("idempotency_key")
        self._assert_error_contains(self._call_disable(controller, missing), "idempotency_key")

        first = self._call_disable(controller, dict(payload))
        second = self._call_disable(controller, dict(payload))
        self.assertIn("False", repr(first))
        self.assertIn("False", repr(second))

        station.invalidate_recordset(["active", "disable_idempotency_key", "disable_request_hash"])
        self.assertFalse(station.active)
        self.assertEqual(station.disable_idempotency_key, key)
        self.assertTrue(station.disable_request_hash)

        conflict = self._call_disable(
            controller,
            self._disable_payload(station, key=key, client_nonce="different"),
        )
        self._assert_error_contains(conflict, "idempotency_conflict")

    def test_station_disable_requires_action_code_and_trusted_device(self):
        station = self._create_station_direct("disable-guard-25b")

        controller, _manager, _session = self._admin_controller("admin-station-disable-action-25b@example.com")
        missing = self._disable_payload(station, key="station-disable-missing-action-25b")
        missing.pop("action_code")
        self._assert_error_contains(self._call_disable(controller, missing), "action_code")

        for alias in ("action_pin", "pin", "secret_code"):
            payload = self._disable_payload(station, key="station-disable-alias-%s-25b" % alias)
            payload.pop("action_code")
            payload[alias] = "1234"
            self._assert_error_contains(self._call_disable(controller, payload), "action_code")

        untrusted_controller, _manager2, _session2 = self._admin_controller(
            "admin-station-disable-untrusted-25b@example.com",
            trusted=False,
        )
        response = self._call_disable(
            untrusted_controller,
            self._disable_payload(station, key="station-disable-untrusted-25b"),
        )
        self._assert_error_contains(response, "Device mobile en attente de validation")
