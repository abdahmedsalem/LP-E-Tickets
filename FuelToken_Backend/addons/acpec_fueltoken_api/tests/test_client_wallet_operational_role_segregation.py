# -*- coding: utf-8 -*-
import base64

from odoo.exceptions import ValidationError
from odoo.tests.common import TransactionCase, tagged


def _acpec_test_mobile_phone(label):
    value = 3466136261
    for char in str(label):
        value ^= ord(char)
        value = (value * 16777619) % 10000000
    return "4%07d" % value


@tagged("post_install", "-at_install")
class TestClientWalletOperationalRoleSegregation(TransactionCase):
    # H0E: a partner carrying active FuelToken value must not be represented
    # by an operational mobile user: station or manager.

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

    def _base_mobile_group_ids(self):
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

    def _create_mobile_user(self, label, group_ids=None):
        user_model = self.env["res.users"].sudo().with_context(
            acpec_mobile_allow_password_write=True,
            no_reset_password=True,
        )
        login = "%s@example.com" % label
        user = user_model.create({
            "name": label,
            "login": _acpec_test_mobile_phone(label),
            "mobile_phone": _acpec_test_mobile_phone(label),
            "email": login,
            "active": True,
            "company_id": self.company.id,
            "company_ids": [(6, 0, [self.company.id])],
            "mobile_only": True,
            "mobile_state": "approved",
            "password": user_model._acpec_mobile_unusable_password(),
            "group_ids": [(6, 0, group_ids or self._base_mobile_group_ids())],
        })
        if user.partner_id:
            user.partner_id.sudo().write({
                "name": "Partner %s" % label,
                "company_id": self.company.id,
            })
        return user

    def _create_unique_carnet_type(self):
        carnet_model = self.env["acpec.fuel.carnet.type"].sudo()
        face_count = 10
        for face_value in range(970001, 970701):
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
        self.fail("Impossible de créer un type de carnet isolé pour H0E.")

    def _create_submitted_purchase_for_partner(self, partner, suffix):
        carnet_type = self._create_unique_carnet_type()
        purchase = self.env["acpec.fuel.purchase"].sudo().create({
            "partner_id": partner.id,
            "company_id": self.company.id,
            "payment_reference": "PAY-H0E-%s" % suffix,
        })
        self.env["acpec.fuel.purchase.line"].sudo().create({
            "purchase_id": purchase.id,
            "carnet_type_id": carnet_type.id,
            "carnet_qty": 1,
        })
        attachment = self.env["ir.attachment"].sudo().create({
            "name": "preuve-h0e.pdf",
            "datas": base64.b64encode(b"%PDF-1.4\npreuve h0e\n").decode("ascii"),
            "mimetype": "application/pdf",
            "res_model": purchase._name,
            "res_id": purchase.id,
            "type": "binary",
        })
        purchase.write({"proof_attachment_ids": [(4, attachment.id)]})
        purchase.action_submit()
        purchase.invalidate_recordset(["state"])
        self.assertEqual(purchase.state, "submitted")
        return purchase

    def _approve_purchase_for_partner(self, partner, suffix):
        purchase = self._create_submitted_purchase_for_partner(partner, suffix)
        purchase.action_approve()
        purchase.invalidate_recordset(["state"])
        self.assertEqual(purchase.state, "approved")
        lines = self.env["acpec.fuel.face.line"].sudo().search([
            ("wallet_id.partner_id", "=", partner.id),
            ("qty_available", ">", 0),
        ])
        self.assertTrue(lines)
        return purchase

    def test_partner_with_non_empty_wallet_cannot_become_mobile_manager(self):
        user = self._create_mobile_user("h0e-client-to-manager")
        self._approve_purchase_for_partner(user.partner_id, "client-to-manager")

        manager_group = self.env.ref("acpec_fueltoken_base.group_fuel_manager")
        with self.assertRaises(ValidationError):
            user.sudo().write({"group_ids": [(4, manager_group.id)]})

    def test_partner_with_non_empty_wallet_cannot_become_station_user(self):
        user = self._create_mobile_user("h0e-client-to-station")
        self._approve_purchase_for_partner(user.partner_id, "client-to-station")

        station_group = self.env.ref("acpec_fueltoken_base.group_fuel_station")
        with self.assertRaises(ValidationError):
            user.sudo().write({"group_ids": [(4, station_group.id)]})

    def test_station_assignment_rejects_operational_user_with_non_empty_wallet(self):
        station_user = self._create_mobile_user(
            "h0e-station-assignment",
            group_ids=self._station_group_ids(),
        )
        self._approve_purchase_for_partner(station_user.partner_id, "station-assignment")

        with self.assertRaises(ValidationError):
            self.env["acpec.fuel.station"].sudo().create({
                "name": "Station H0E",
                "code": "ST-H0E",
                "user_id": station_user.id,
                "company_id": self.company.id,
            })

    def test_device_trust_rejects_operational_user_with_non_empty_wallet(self):
        station_user = self._create_mobile_user(
            "h0e-device-station",
            group_ids=self._station_group_ids(),
        )
        self._approve_purchase_for_partner(station_user.partner_id, "device-station")

        token_data = self.env["acpec.mobile.session"].sudo().create_for_user(station_user, {
            "device_uid": "dev-h0e-device-station",
            "platform": "android",
        })
        session = token_data["session"]

        with self.assertRaises(ValidationError):
            session.action_trust_device()
