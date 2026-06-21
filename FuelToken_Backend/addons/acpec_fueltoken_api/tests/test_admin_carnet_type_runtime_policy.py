# -*- coding: utf-8 -*-
from types import SimpleNamespace
from unittest.mock import patch

from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_fueltoken_api.controllers import api_admin as api_admin_module
from odoo.addons.acpec_fueltoken_api.controllers.api_admin import AcpecFuelTokenAdminApi


@tagged("post_install", "-at_install")
class TestAdminCarnetTypeRuntimePolicy(TransactionCase):
    # Runtime policy coverage for admin carnet type create/update/delete.
    # Carnet type admin decisions require trusted manager device, action_code,
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

    def _create_manager_user(self, login):
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
            "group_ids": [(6, 0, self._manager_group_ids())],
        })
        user.set_mobile_pin("1234")
        return user

    def _admin_controller(self, login, trusted=True):
        manager = self._create_manager_user(login)
        token_data = self.env["acpec.mobile.session"].sudo().create_for_user(manager, {
            "device_uid": "dev-admin-carnet-%s" % login.replace("@", "-").replace(".", "-"),
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
            return controller.carnet_type_create(**payload)

    def _call_update(self, controller, payload):
        fake_request = SimpleNamespace(env=self.env)
        with patch.object(api_admin_module, "request", fake_request):
            return controller.carnet_type_update(**payload)

    def _call_delete(self, controller, payload):
        fake_request = SimpleNamespace(env=self.env)
        with patch.object(api_admin_module, "request", fake_request):
            return controller.carnet_type_delete(**payload)

    def _assert_error_contains(self, response, expected):
        self.assertIn(expected, repr(response))
        self.assertIn("success", repr(response))
        self.assertIn("False", repr(response))

    def _create_payload(self, key="admin-carnet-create-key", face_value=970001, **extra):
        payload = {
            "name": "Carnet runtime create 25C",
            "code": "CT25CCREATE",
            "face_count": 10,
            "face_value": face_value,
            "validity_days": 365,
            "company_id": self.company.id,
            "active": True,
            "action_code": "1234",
            "idempotency_key": key,
        }
        payload.update(extra)
        return payload

    def _update_payload(self, carnet_type, key="admin-carnet-update-key", **extra):
        payload = {
            "carnet_type_id": carnet_type.id,
            "name": "Carnet runtime updated 25C",
            "code": "CT25CUPDATED%s" % carnet_type.id,
            "validity_days": 180,
            "action_code": "1234",
            "idempotency_key": key,
        }
        payload.update(extra)
        return payload

    def _delete_payload(self, carnet_type, key="admin-carnet-delete-key", **extra):
        payload = {
            "carnet_type_id": carnet_type.id,
            "action_code": "1234",
            "idempotency_key": key,
        }
        payload.update(extra)
        return payload

    def _carnet_by_create_key(self, key):
        return self.env["acpec.fuel.carnet.type"].sudo().search([
            ("admin_create_idempotency_key", "=", key),
        ])

    def _create_carnet_direct(self, suffix, face_value):
        return self.env["acpec.fuel.carnet.type"].sudo().create({
            "name": "Carnet direct %s" % suffix,
            "code": "CT25C%s" % suffix.upper().replace("-", "")[:20],
            "face_count": 10,
            "face_value": face_value,
            "validity_days": 365,
            "company_id": self.company.id,
            "active": True,
        })

    def test_carnet_type_create_requires_action_code_only(self):
        controller, _manager, _session = self._admin_controller("admin-carnet-create-action-25c@example.com")

        missing = self._create_payload(key="carnet-create-missing-action-25c", face_value=970101)
        missing.pop("action_code")
        self._assert_error_contains(self._call_create(controller, missing), "action_code")
        self.assertFalse(self._carnet_by_create_key("carnet-create-missing-action-25c"))

        for idx, alias in enumerate(("action_pin", "pin", "secret_code"), start=1):
            key = "carnet-create-alias-%s-25c" % alias
            payload = self._create_payload(key=key, face_value=970101 + idx)
            payload.pop("action_code")
            payload[alias] = "1234"
            self._assert_error_contains(self._call_create(controller, payload), "action_code")
            self.assertFalse(self._carnet_by_create_key(key))

    def test_carnet_type_create_requires_idempotency_key(self):
        controller, _manager, _session = self._admin_controller("admin-carnet-create-idem-25c@example.com")

        payload = self._create_payload(key="carnet-create-will-be-removed-25c", face_value=970111)
        payload.pop("idempotency_key")
        self._assert_error_contains(self._call_create(controller, payload), "idempotency_key")
        self.assertFalse(self._carnet_by_create_key("carnet-create-will-be-removed-25c"))

    def test_carnet_type_create_requires_trusted_manager_device(self):
        controller, _manager, _session = self._admin_controller(
            "admin-carnet-create-untrusted-25c@example.com",
            trusted=False,
        )
        key = "carnet-create-untrusted-25c"
        response = self._call_create(
            controller,
            self._create_payload(key=key, face_value=970121),
        )
        self._assert_error_contains(response, "Device mobile en attente de validation")
        self.assertFalse(self._carnet_by_create_key(key))

    def test_carnet_type_create_replays_same_payload_for_same_idempotency_key(self):
        controller, _manager, _session = self._admin_controller("admin-carnet-create-replay-25c@example.com")
        key = "carnet-create-replay-key-25c"
        payload = self._create_payload(
            key=key,
            face_value=970131,
            name="Carnet replay 25C",
            code="CT25CREPLAY",
        )

        first = self._call_create(controller, dict(payload))
        second = self._call_create(controller, dict(payload))
        self.assertIn("'success': True", repr(first))
        self.assertIn("'success': True", repr(second))

        records = self._carnet_by_create_key(key)
        self.assertEqual(len(records), 1)
        self.assertEqual(records.face_count, 10)
        self.assertEqual(records.face_value, 970131)
        self.assertTrue(records.admin_create_request_hash)

    def test_carnet_type_create_rejects_same_key_with_different_payload(self):
        controller, _manager, _session = self._admin_controller("admin-carnet-create-conflict-25c@example.com")
        key = "carnet-create-conflict-key-25c"

        first = self._call_create(
            controller,
            self._create_payload(key=key, face_value=970141, name="Carnet conflict A", code="CT25CCONFA"),
        )
        self.assertNotIn("idempotency_conflict", repr(first))

        second = self._call_create(
            controller,
            self._create_payload(key=key, face_value=970142, name="Carnet conflict B", code="CT25CCONFB"),
        )
        self._assert_error_contains(second, "idempotency_conflict")
        self.assertEqual(len(self._carnet_by_create_key(key)), 1)

    def test_carnet_type_update_requires_idempotency_and_replay_conflict(self):
        controller, _manager, _session = self._admin_controller("admin-carnet-update-25c@example.com")
        carnet_type = self._create_carnet_direct("update-25c", 970201)
        key = "carnet-update-replay-key-25c"
        payload = self._update_payload(carnet_type, key=key, name="Carnet updated replay 25C")

        missing = dict(payload)
        missing.pop("idempotency_key")
        self._assert_error_contains(self._call_update(controller, missing), "idempotency_key")

        first = self._call_update(controller, dict(payload))
        second = self._call_update(controller, dict(payload))
        self.assertIn("'success': True", repr(first))
        self.assertIn("'success': True", repr(second))

        carnet_type.invalidate_recordset([
            "validity_days", "admin_update_idempotency_key", "admin_update_request_hash",
        ])
        self.assertEqual(carnet_type.validity_days, 180)
        self.assertEqual(carnet_type.admin_update_idempotency_key, key)
        self.assertTrue(carnet_type.admin_update_request_hash)

        conflict = self._call_update(
            controller,
            self._update_payload(carnet_type, key=key, validity_days=181),
        )
        self._assert_error_contains(conflict, "idempotency_conflict")
        carnet_type.invalidate_recordset(["validity_days"])
        self.assertEqual(carnet_type.validity_days, 180)

    def test_carnet_type_update_requires_action_code_and_trusted_device(self):
        carnet_type = self._create_carnet_direct("update-guard-25c", 970211)

        controller, _manager, _session = self._admin_controller("admin-carnet-update-action-25c@example.com")
        missing = self._update_payload(carnet_type, key="carnet-update-missing-action-25c")
        missing.pop("action_code")
        self._assert_error_contains(self._call_update(controller, missing), "action_code")

        for alias in ("action_pin", "pin", "secret_code"):
            payload = self._update_payload(carnet_type, key="carnet-update-alias-%s-25c" % alias)
            payload.pop("action_code")
            payload[alias] = "1234"
            self._assert_error_contains(self._call_update(controller, payload), "action_code")

        untrusted_controller, _manager2, _session2 = self._admin_controller(
            "admin-carnet-update-untrusted-25c@example.com",
            trusted=False,
        )
        response = self._call_update(
            untrusted_controller,
            self._update_payload(carnet_type, key="carnet-update-untrusted-25c"),
        )
        self._assert_error_contains(response, "Device mobile en attente de validation")

    def test_carnet_type_delete_requires_idempotency_and_replay_conflict(self):
        controller, _manager, _session = self._admin_controller("admin-carnet-delete-25c@example.com")
        carnet_type = self._create_carnet_direct("delete-25c", 970301)
        key = "carnet-delete-replay-key-25c"
        payload = self._delete_payload(carnet_type, key=key)

        missing = dict(payload)
        missing.pop("idempotency_key")
        self._assert_error_contains(self._call_delete(controller, missing), "idempotency_key")

        first = self._call_delete(controller, dict(payload))
        second = self._call_delete(controller, dict(payload))
        self.assertIn("False", repr(first))
        self.assertIn("False", repr(second))

        carnet_type.invalidate_recordset(["active", "admin_delete_idempotency_key", "admin_delete_request_hash"])
        self.assertFalse(carnet_type.active)
        self.assertEqual(carnet_type.admin_delete_idempotency_key, key)
        self.assertTrue(carnet_type.admin_delete_request_hash)

        conflict = self._call_delete(
            controller,
            self._delete_payload(carnet_type, key=key, client_nonce="different"),
        )
        self._assert_error_contains(conflict, "idempotency_conflict")

    def test_carnet_type_delete_requires_action_code_and_trusted_device(self):
        carnet_type = self._create_carnet_direct("delete-guard-25c", 970311)

        controller, _manager, _session = self._admin_controller("admin-carnet-delete-action-25c@example.com")
        missing = self._delete_payload(carnet_type, key="carnet-delete-missing-action-25c")
        missing.pop("action_code")
        self._assert_error_contains(self._call_delete(controller, missing), "action_code")

        for alias in ("action_pin", "pin", "secret_code"):
            payload = self._delete_payload(carnet_type, key="carnet-delete-alias-%s-25c" % alias)
            payload.pop("action_code")
            payload[alias] = "1234"
            self._assert_error_contains(self._call_delete(controller, payload), "action_code")

        untrusted_controller, _manager2, _session2 = self._admin_controller(
            "admin-carnet-delete-untrusted-25c@example.com",
            trusted=False,
        )
        response = self._call_delete(
            untrusted_controller,
            self._delete_payload(carnet_type, key="carnet-delete-untrusted-25c"),
        )
        self._assert_error_contains(response, "Device mobile en attente de validation")
