# -*- coding: utf-8 -*-
from types import SimpleNamespace
from unittest.mock import patch

from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_fueltoken_api.controllers import api_admin as api_admin_module
from odoo.addons.acpec_fueltoken_api.controllers.api_admin import AcpecFuelTokenAdminApi


def _acpec_test_mobile_phone(label):
    value = 2166136261
    for char in str(label):
        value ^= ord(char)
        value = (value * 16777619) % 10000000
    return "3%07d" % value


@tagged("post_install", "-at_install")
class TestAdminDevicePositiveValidatorPolicy(TransactionCase):

    def _group_ids(self, xmlids):
        ids = []
        for xmlid in xmlids:
            group = self.env.ref(xmlid, raise_if_not_found=False)
            if group:
                ids.append(group.id)
        return ids

    def _create_mobile_user(self, label, manager=False):
        user_model = self.env["res.users"].sudo().with_context(
            acpec_mobile_allow_password_write=True,
            no_reset_password=True,
        )
        xmlids = [
            "base.group_portal",
            "acpec_mobile_auth.group_mobile_auth_user",
        ]
        if manager:
            xmlids.append("acpec_fueltoken_base.group_fuel_manager")
        user = user_model.create({
            "name": label,
            "login": _acpec_test_mobile_phone(label),
            "mobile_phone": _acpec_test_mobile_phone(label),
            "email": label,
            "active": True,
            "company_id": self.env.company.id,
            "company_ids": [(6, 0, [self.env.company.id])],
            "mobile_only": True,
            "mobile_state": "approved",
            "password": user_model._acpec_mobile_unusable_password(),
            "group_ids": [(6, 0, self._group_ids(xmlids))],
        })
        user.set_mobile_pin("1234")
        return user

    def _create_session(self, user, device_uid, trusted=False):
        token_data = self.env["acpec.mobile.session"].sudo().create_for_user(user, {
            "device_uid": device_uid,
            "device_name": device_uid,
            "platform": "android",
        })
        session = token_data["session"]
        if trusted:
            session.sudo().action_trust_device()
        return session

    def _controller(self, session):
        controller = AcpecFuelTokenAdminApi()
        controller._test_env = self.env
        controller._get_mobile_session = lambda required=True: session
        return controller

    def _call(self, controller, method_name, payload=None):
        fake_request = SimpleNamespace(env=self.env)
        with patch.object(api_admin_module, "request", fake_request):
            return getattr(controller, method_name)(**(payload or {}))

    def _assert_success(self, response):
        self.assertIn("success", repr(response))
        self.assertIn("True", repr(response))

    def _assert_error_contains(self, response, expected):
        self.assertIn("success", repr(response))
        self.assertIn("False", repr(response))
        self.assertIn(expected, repr(response))

    def test_manager_can_list_pending_trust_devices(self):
        manager = self._create_mobile_user("h0c-device-list-manager@example.com", manager=True)
        manager_session = self._create_session(manager, "ft-h0c-device-list-manager", trusted=True)
        target = self._create_mobile_user("h0c-device-list-target@example.com")
        target_session = self._create_session(target, "ft-h0c-device-list-target", trusted=False)

        response = self._call(self._controller(manager_session), "devices_pending_trust", {})
        self._assert_success(response)
        self.assertIn(target_session.device_id.stable_device_uid, repr(response))

    def test_manager_can_approve_pending_trust_device(self):
        manager = self._create_mobile_user("h0c-device-approve-manager@example.com", manager=True)
        manager_session = self._create_session(manager, "ft-h0c-device-approve-manager", trusted=True)
        target = self._create_mobile_user("h0c-device-approve-target@example.com")
        target_session = self._create_session(target, "ft-h0c-device-approve-target", trusted=False)
        device = target_session.device_id

        response = self._call(self._controller(manager_session), "device_approve_pending_trust", {
            "device_id": device.id,
            "action_code": "1234",
            "idempotency_key": "h0c-device-approve-key",
        })
        self._assert_success(response)
        device.invalidate_recordset(["trust_state", "trusted_by"])
        target_session.invalidate_recordset(["device_trust_state"])
        self.assertEqual(device.trust_state, "trusted")
        self.assertEqual(target_session.device_trust_state, "trusted")
        self.assertEqual(device.trusted_by.id, manager.id)

    def test_manager_cannot_approve_own_pending_device(self):
        manager = self._create_mobile_user("h0c-device-own-manager@example.com", manager=True)
        manager_session = self._create_session(manager, "ft-h0c-device-own-manager-a", trusted=True)
        own_pending = self._create_session(manager, "ft-h0c-device-own-manager-b", trusted=False)

        response = self._call(self._controller(manager_session), "device_approve_pending_trust", {
            "device_id": own_pending.device_id.id,
            "action_code": "1234",
            "idempotency_key": "h0c-device-own-key",
        })
        self._assert_error_contains(response, "propre device")
        own_pending.device_id.invalidate_recordset(["trust_state"])
        self.assertEqual(own_pending.device_id.trust_state, "pending_trust")
