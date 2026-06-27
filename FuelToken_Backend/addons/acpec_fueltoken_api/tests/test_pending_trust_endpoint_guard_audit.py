# -*- coding: utf-8 -*-
from types import SimpleNamespace
from unittest.mock import patch


def _acpec_test_mobile_phone(label):
    """Return a deterministic canonical 8-digit mobile phone for test labels."""
    value = 2166136261
    for char in str(label):
        value ^= ord(char)
        value = (value * 16777619) % 10000000
    return "3%07d" % value


from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_fueltoken_api.controllers import api_admin as api_admin_module
from odoo.addons.acpec_fueltoken_api.controllers import api_mobile as api_mobile_module
from odoo.addons.acpec_fueltoken_api.controllers import api_station as api_station_module
from odoo.addons.acpec_fueltoken_api.controllers.api_admin import AcpecFuelTokenAdminApi
from odoo.addons.acpec_fueltoken_api.controllers.api_mobile import AcpecFuelTokenMobileApi
from odoo.addons.acpec_fueltoken_api.controllers.api_station import AcpecFuelTokenStationApi


@tagged("post_install", "-at_install")
class TestPendingTrustEndpointGuardAudit(TransactionCase):
    """Patch43F2O.

    pending_trust is a device runtime state, not a business role state.

    A user may keep FuelToken groups while the current device is pending_trust.
    The protection must be enforced by the trusted-device runtime guard, not by
    removing FuelToken groups from the user.
    """

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

    def _create_mobile_user(self, label, role_xmlid):
        phone = _acpec_test_mobile_phone(label)
        group_ids = self._group_ids([
            "base.group_portal",
            "acpec_mobile_auth.group_mobile_auth_user",
            role_xmlid,
        ])
        user_model = self.env["res.users"].sudo().with_context(
            acpec_mobile_allow_password_write=True,
            no_reset_password=True,
        )
        user = user_model.create({
            "name": "F2O %s" % label,
            "login": phone,
            "mobile_phone": phone,
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

    def _pending_session(self, user, label):
        result = self.env["acpec.mobile.session"].sudo().create_for_user(user, {
            "device_uid": "ft-f2o-pending-%s" % label,
            "device_name": "F2O pending %s" % label,
            "platform": "android",
            "app_version": "1.0.0",
        })
        session = result["session"] if isinstance(result, dict) else result
        self.assertEqual(session.device_trust_state, "pending_trust")
        return session

    def _assert_pending_refused(self, response):
        self.assertFalse(response.get("success"))
        self.assertEqual(response.get("error", {}).get("code"), "ACCESS_ERROR")
        self.assertIn(
            "Device mobile en attente de validation",
            response.get("error", {}).get("message") or "",
        )

    def _assert_group_still_present(self, user, role_xmlid):
        role = self.env.ref(role_xmlid)
        user.invalidate_recordset(["group_ids"])
        self.assertIn(role, user.group_ids)

    def test_f2o_pending_client_keeps_fuel_group_but_cannot_read_wallet(self):
        role_xmlid = "acpec_fueltoken_base.group_fuel_user"
        user = self._create_mobile_user("client", role_xmlid)
        session = self._pending_session(user, "client")

        controller = AcpecFuelTokenMobileApi()
        controller._test_env = self.env
        controller._get_mobile_session = lambda required=True: session

        fake_request = SimpleNamespace(env=self.env)
        with patch.object(api_mobile_module, "request", fake_request):
            response = controller.current_wallet()

        self._assert_pending_refused(response)
        self._assert_group_still_present(user, role_xmlid)
        session.invalidate_recordset(["device_trust_state"])
        self.assertEqual(session.device_trust_state, "pending_trust")

    def test_f2o_pending_station_keeps_fuel_group_but_cannot_read_station_profile(self):
        role_xmlid = "acpec_fueltoken_base.group_fuel_station"
        user = self._create_mobile_user("station", role_xmlid)
        session = self._pending_session(user, "station")

        controller = AcpecFuelTokenStationApi()
        controller._test_env = self.env
        controller._get_mobile_session = lambda required=True: session

        fake_request = SimpleNamespace(env=self.env)
        with patch.object(api_station_module, "request", fake_request):
            response = controller.profile()

        self._assert_pending_refused(response)
        self._assert_group_still_present(user, role_xmlid)
        session.invalidate_recordset(["device_trust_state"])
        self.assertEqual(session.device_trust_state, "pending_trust")

    def test_f2o_pending_manager_keeps_fuel_group_but_cannot_read_admin_data(self):
        role_xmlid = "acpec_fueltoken_base.group_fuel_manager"
        user = self._create_mobile_user("manager", role_xmlid)
        session = self._pending_session(user, "manager")

        controller = AcpecFuelTokenAdminApi()
        controller._test_env = self.env
        controller._get_mobile_session = lambda required=True: session

        fake_request = SimpleNamespace(env=self.env)
        with patch.object(api_admin_module, "request", fake_request):
            response = controller.carnet_type_list()

        self._assert_pending_refused(response)
        self._assert_group_still_present(user, role_xmlid)
        session.invalidate_recordset(["device_trust_state"])
        self.assertEqual(session.device_trust_state, "pending_trust")
