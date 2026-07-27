# -*- coding: utf-8 -*-
from odoo.exceptions import AccessError
from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_mobile_auth.controllers.api_common import AcpecMobileAuthApiCommon


def _acpec_test_mobile_phone(label):
    value = 2766136261
    for char in str(label):
        value ^= ord(char)
        value = (value * 16777619) % 10000000
    return "3%07d" % value


@tagged("post_install", "-at_install", "patch2s_backend_guard")
class TestClientMobileRoleExclusiveGuard(TransactionCase):
    """Patch2S-B: client mobile endpoints reject operational mobile roles."""

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

    def _create_mobile_user(self, label, xmlids):
        user_model = self.env["res.users"].sudo().with_context(
            acpec_mobile_allow_password_write=True,
            no_reset_password=True,
        )
        phone = _acpec_test_mobile_phone(label)
        user = user_model.create({
            "name": label,
            "login": phone,
            "mobile_phone": phone,
            "email": "%s@example.com" % label,
            "active": True,
            "company_id": self.company.id,
            "company_ids": [(6, 0, [self.company.id])],
            "acpec_mobile_only": True,
            "acpec_mobile_state": "approved",
            "password": user_model._acpec_mobile_unusable_password(),
            "group_ids": [(6, 0, self._group_ids([
                "base.group_portal",
                "acpec_mobile_auth.group_mobile_auth_user",
            ] + list(xmlids)))],
        })
        if user.partner_id:
            user.partner_id.sudo().write({"company_id": self.company.id})
        return user

    def _controller(self):
        controller = AcpecMobileAuthApiCommon()
        controller._test_env = self.env
        return controller

    def test_plain_client_is_accepted_for_client_role(self):
        user = self._create_mobile_user("patch2s-plain-client", [
            "acpec_fueltoken_base.group_fuel_user",
        ])
        self.assertTrue(self._controller()._require_fuel_group(user, "client"))

    def test_station_with_client_group_is_rejected_for_client_role(self):
        user = self._create_mobile_user("patch2s-station-client", [
            "acpec_fueltoken_base.group_fuel_user",
            "acpec_fueltoken_base.group_fuel_station",
        ])
        with self.assertRaises(AccessError):
            self._controller()._require_fuel_group(user, "client")

    def test_manager_with_client_group_is_rejected_for_client_role(self):
        user = self._create_mobile_user("patch2s-manager-client", [
            "acpec_fueltoken_base.group_fuel_user",
            "acpec_fueltoken_base.group_fuel_manager",
        ])
        with self.assertRaises(AccessError):
            self._controller()._require_fuel_group(user, "client")


    def test_operational_only_roles_are_rejected_for_client_role(self):
        cases = [
            ("patch2s-station-only", "acpec_fueltoken_base.group_fuel_station"),
            ("patch2s-manager-only", "acpec_fueltoken_base.group_fuel_manager"),
        ]
        for label, xmlid in cases:
            user = self._create_mobile_user(label, [xmlid])
            with self.assertRaises(AccessError):
                self._controller()._require_fuel_group(user, "client")
