# -*- coding: utf-8 -*-
from types import SimpleNamespace
from unittest.mock import patch

from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_fueltoken_api.controllers import api_admin as api_admin_module
from odoo.addons.acpec_fueltoken_api.controllers import api_mobile as api_mobile_module
from odoo.addons.acpec_fueltoken_api.controllers import api_station as api_station_module
from odoo.addons.acpec_fueltoken_api.controllers.api_admin import AcpecFuelTokenAdminApi
from odoo.addons.acpec_fueltoken_api.controllers.api_mobile import AcpecFuelTokenMobileApi
from odoo.addons.acpec_fueltoken_api.controllers.api_station import AcpecFuelTokenStationApi


@tagged("post_install", "-at_install")
class TestTrustedReadGateRuntimePolicy(TransactionCase):
    # Runtime coverage for INV-D8: business reads require a trusted device.
    # These tests deliberately use pending_trust sessions and assert the read
    # wall triggers before wallet/admin/station business data is returned.

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

    def _mobile_group_ids(self):
        return self._group_ids([
            "base.group_portal",
            "acpec_mobile_auth.group_mobile_auth_user",
            "acpec_fueltoken_base.group_fuel_user",
        ])

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

    def _pending_session(self, user, suffix):
        token_data = self.env["acpec.mobile.session"].sudo().create_for_user(user, {
            "device_uid": "dev-read-wall-%s" % suffix,
            "platform": "android",
        })
        session = token_data["session"]
        self.assertEqual(session.device_trust_state, "pending_trust")
        return session

    def _assert_pending_read_refused(self, response):
        self.assertFalse(response.get("success"))
        self.assertEqual(response.get("error", {}).get("code"), "ACCESS_ERROR")
        self.assertIn("Device mobile en attente de validation", response.get("error", {}).get("message") or "")

    def test_pending_client_device_cannot_read_wallet(self):
        user = self._create_mobile_user(
            "read-wall-client-43b@example.com",
            self._mobile_group_ids(),
        )
        session = self._pending_session(user, "client-43b")
        controller = AcpecFuelTokenMobileApi()
        controller._test_env = self.env
        controller._get_mobile_session = lambda required=True: session

        fake_request = SimpleNamespace(env=self.env)
        with patch.object(api_mobile_module, "request", fake_request):
            response = controller.current_wallet()

        self._assert_pending_read_refused(response)

    def test_pending_station_device_cannot_check_qr(self):
        user = self._create_mobile_user(
            "read-wall-station-43b@example.com",
            self._station_group_ids(),
        )
        session = self._pending_session(user, "station-43b")
        controller = AcpecFuelTokenStationApi()
        controller._test_env = self.env
        controller._get_mobile_session = lambda required=True: session

        fake_request = SimpleNamespace(env=self.env)
        with patch.object(api_station_module, "request", fake_request):
            response = controller.check_qr(public_code="QR-NOT-NEEDED-BEFORE-TRUST")

        self._assert_pending_read_refused(response)

    def test_pending_manager_device_cannot_read_admin_summary(self):
        user = self._create_mobile_user(
            "read-wall-manager-43b@example.com",
            self._manager_group_ids(),
        )
        session = self._pending_session(user, "manager-43b")
        controller = AcpecFuelTokenAdminApi()
        controller._test_env = self.env
        controller._get_mobile_session = lambda required=True: session

        fake_request = SimpleNamespace(env=self.env)
        with patch.object(api_admin_module, "request", fake_request):
            response = controller.reports_summary()

        self._assert_pending_read_refused(response)
