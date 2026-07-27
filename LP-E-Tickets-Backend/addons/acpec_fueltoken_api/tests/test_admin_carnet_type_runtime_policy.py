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
class TestAdminCarnetTypeRuntimePolicy(TransactionCase):

    def _group_ids(self, xmlids):
        ids = []
        for xmlid in xmlids:
            group = self.env.ref(xmlid, raise_if_not_found=False)
            if group:
                ids.append(group.id)
        return ids

    def _create_manager_user(self, login):
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
            "company_id": self.env.company.id,
            "company_ids": [(6, 0, [self.env.company.id])],
            "acpec_mobile_only": True,
            "acpec_mobile_state": "approved",
            "password": user_model._acpec_mobile_unusable_password(),
            "group_ids": [(6, 0, self._group_ids([
                "base.group_portal",
                "acpec_mobile_auth.group_mobile_auth_user",
                "acpec_fueltoken_base.group_fuel_manager",
            ]))],
        })
        user.set_mobile_pin("1234")
        return user

    def _controller(self, label):
        manager = self._create_manager_user(label)
        token_data = self.env["acpec.mobile.session"].sudo().create_for_user(manager, {
            "device_uid": "dev-h0c-%s" % label.replace("@", "-").replace(".", "-"),
            "platform": "android",
        })
        session = token_data["session"]
        session.sudo().action_trust_device()
        controller = AcpecFuelTokenAdminApi()
        controller._test_env = self.env
        controller._get_mobile_session = lambda required=True: session
        return controller

    def _call(self, controller, method_name, payload=None):
        fake_request = SimpleNamespace(env=self.env)
        with patch.object(api_admin_module, "request", fake_request):
            return getattr(controller, method_name)(**(payload or {}))

    def _assert_backoffice_only(self, response):
        self.assertIn("success", repr(response))
        self.assertIn("False", repr(response))
        self.assertIn("back-office", repr(response))

    def test_carnet_type_list_is_backoffice_only_for_mobile_manager(self):
        controller = self._controller("h0c-carnet_type_list@example.com")
        response = self._call(controller, "carnet_type_list", {
            "action_code": "1234",
            "idempotency_key": "h0c-carnet_type_list-key",
        })
        self._assert_backoffice_only(response)

    def test_carnet_type_create_is_backoffice_only_for_mobile_manager(self):
        controller = self._controller("h0c-carnet_type_create@example.com")
        response = self._call(controller, "carnet_type_create", {
            "action_code": "1234",
            "idempotency_key": "h0c-carnet_type_create-key",
        })
        self._assert_backoffice_only(response)

    def test_carnet_type_update_is_backoffice_only_for_mobile_manager(self):
        controller = self._controller("h0c-carnet_type_update@example.com")
        response = self._call(controller, "carnet_type_update", {
            "action_code": "1234",
            "idempotency_key": "h0c-carnet_type_update-key",
        })
        self._assert_backoffice_only(response)

    def test_carnet_type_delete_is_backoffice_only_for_mobile_manager(self):
        controller = self._controller("h0c-carnet_type_delete@example.com")
        response = self._call(controller, "carnet_type_delete", {
            "action_code": "1234",
            "idempotency_key": "h0c-carnet_type_delete-key",
        })
        self._assert_backoffice_only(response)

