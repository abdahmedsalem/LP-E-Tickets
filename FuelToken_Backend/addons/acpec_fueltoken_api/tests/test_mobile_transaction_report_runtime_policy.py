# -*- coding: utf-8 -*-
from types import SimpleNamespace
from unittest.mock import patch

from odoo import fields
from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_fueltoken_api.controllers import api_mobile as api_mobile_module
from odoo.addons.acpec_fueltoken_api.controllers.api_mobile import AcpecFuelTokenMobileApi


def _acpec_test_mobile_phone(label):
    value = 61687191
    for char in str(label):
        value ^= ord(char)
        value = (value * 16777619) % 10000000
    return "3%07d" % value


@tagged("post_install", "-at_install")
class TestMobileTransactionReportRuntimePolicy(TransactionCase):

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

    def _create_mobile_user(self, login):
        phone = _acpec_test_mobile_phone(login)
        user_model = self.env["res.users"].sudo().with_context(
            acpec_mobile_allow_password_write=True,
            no_reset_password=True,
        )
        user = user_model.create({
            "name": login,
            "login": phone,
            "mobile_phone": phone,
            "email": login,
            "active": True,
            "company_id": self.company.id,
            "company_ids": [(6, 0, [self.company.id])],
            "mobile_only": True,
            "mobile_state": "approved",
            "password": user_model._acpec_mobile_unusable_password(),
            "group_ids": [(6, 0, self._mobile_group_ids())],
        })
        user.set_mobile_pin("1234")
        return user

    def _controller_for_user(self, login):
        user = self._create_mobile_user(login)
        token_data = self.env["acpec.mobile.session"].sudo().create_for_user(user, {
            "device_uid": login.replace("@", "-"),
            "platform": "android",
        })
        session = token_data["session"]
        session.action_trust_device()

        controller = AcpecFuelTokenMobileApi()
        controller._test_env = self.env
        controller._get_mobile_session = lambda required=True: session
        return controller, user, session

    def _wallet_for(self, user):
        return self.env["acpec.fuel.wallet"].sudo().get_or_create(user.partner_id, self.company)

    def _call_transactions(self, controller, payload=None):
        fake_request = SimpleNamespace(env=self.env)
        with patch.object(api_mobile_module, "request", fake_request):
            return controller.transactions(**(payload or {}))

    def _call_transaction_detail(self, controller, transaction_id):
        fake_request = SimpleNamespace(env=self.env)
        with patch.object(api_mobile_module, "request", fake_request):
            return controller.transaction_detail(transaction_id=transaction_id)

    def _response_data(self, response):
        self.assertIsInstance(response, dict)
        data = response.get("data")
        return data if isinstance(data, dict) else response

    def _tx_log(self, tx_type, wallet, **extra):
        return self.env["acpec.fuel.transaction"].sudo().log(
            tx_type,
            self.company,
            wallet=wallet,
            **extra
        )

    def test_patch43m10_mobile_transactions_use_wallet_partner_not_actor_or_counterparty(self):
        controller, user, _session = self._controller_for_user("m10-report-owner@example.com")
        _other_controller, other_user, _other_session = self._controller_for_user("m10-report-other@example.com")

        wallet = self._wallet_for(user)
        other_wallet = self._wallet_for(other_user)

        visible_tx = self._tx_log(
            "emission_qr",
            wallet,
            actor_partner=other_user.partner_id,
            counterparty_partner=False,
            note="visible because wallet partner owns the row",
        )
        actor_only_tx = self._tx_log(
            "emission_qr",
            other_wallet,
            actor_partner=user.partner_id,
            counterparty_partner=False,
            note="must not leak through actor",
        )
        counterparty_only_tx = self._tx_log(
            "emission_qr",
            other_wallet,
            actor_partner=other_user.partner_id,
            counterparty_partner=user.partner_id,
            note="must not leak through counterparty",
        )

        data = self._response_data(self._call_transactions(controller, {"limit": 20}))
        ids = {item["id"] for item in data.get("items", [])}

        self.assertIn(visible_tx.id, ids)
        self.assertNotIn(actor_only_tx.id, ids)
        self.assertNotIn(counterparty_only_tx.id, ids)

    def test_patch43m10_mobile_transaction_payload_has_context_but_no_secrets(self):
        controller, user, session = self._controller_for_user("m10-report-payload@example.com")
        _other_controller, other_user, _other_session = self._controller_for_user("m10-report-counterparty@example.com")
        wallet = self._wallet_for(user)

        tx = self._tx_log(
            "emission_qr",
            wallet,
            actor_partner=user.partner_id,
            counterparty_partner=other_user.partner_id,
            counterparty_user=other_user,
            idempotency_key="secret-idempotency-key",
            request_hash="secret-request-hash",
            note="payload check",
        )
        if "actor_user_id" in tx._fields:
            tx.with_context(allow_fuel_transaction_update=True).write({
                "actor_user_id": user.id,
                "mobile_session_id": session.id,
                "device_uid": session.device_uid,
            })

        data = self._response_data(self._call_transactions(controller, {"limit": 20}))
        items = [item for item in data.get("items", []) if item.get("id") == tx.id]
        self.assertEqual(len(items), 1)
        item = items[0]

        self.assertEqual(item["partner_id"], user.partner_id.id)
        self.assertEqual(item["actor_partner_id"], user.partner_id.id)
        self.assertEqual(item["actor_user_id"], user.id)
        self.assertEqual(item["counterparty_partner_id"], other_user.partner_id.id)
        self.assertEqual(item["counterparty_user_id"], other_user.id)
        self.assertEqual(item["wallet_id"], wallet.id)
        self.assertIn("date", item)
        self.assertIn("regularization_state", item)

        rendered = repr(item)
        self.assertNotIn("secret-idempotency-key", rendered)
        self.assertNotIn("secret-request-hash", rendered)
        self.assertNotIn("qr_numeric_code", rendered)
        self.assertNotIn("qr_numeric_code_hash", rendered)
        self.assertNotIn("device_uid", rendered)
        self.assertNotIn(session.device_uid, rendered)

    def test_patch43m10_mobile_transactions_limit_is_capped_to_100(self):
        controller, user, _session = self._controller_for_user("m10-report-limit@example.com")
        wallet = self._wallet_for(user)

        for index in range(105):
            self._tx_log("emission_qr", wallet, note="limit %s" % index)

        data = self._response_data(self._call_transactions(controller, {"limit": 999}))
        self.assertEqual(data["limit"], 100)
        self.assertEqual(len(data["items"]), 100)
        self.assertTrue(data["has_more"])

    def test_patch43m10_mobile_transactions_rejects_date_to_without_date_from(self):
        controller, _user, _session = self._controller_for_user("m10-report-date-to@example.com")
        response = self._call_transactions(controller, {
            "date_to": fields.Datetime.to_string(fields.Datetime.now()),
        })
        self.assertFalse(response.get("ok"))
        self.assertEqual(response.get("error", {}).get("code"), "VALIDATION_ERROR")

    def test_patch43m10_mobile_transactions_rejects_date_range_over_365_days(self):
        controller, _user, _session = self._controller_for_user("m10-report-date-range@example.com")
        response = self._call_transactions(controller, {
            "date_from": "2024-01-01 00:00:00",
            "date_to": "2025-02-01 00:00:00",
        })
        self.assertFalse(response.get("ok"))
        self.assertEqual(response.get("error", {}).get("code"), "VALIDATION_ERROR")

    def test_patch43m10_mobile_transaction_detail_uses_wallet_partner_scope(self):
        controller, user, _session = self._controller_for_user("m10-report-detail-owner@example.com")
        _other_controller, other_user, _other_session = self._controller_for_user("m10-report-detail-other@example.com")

        wallet = self._wallet_for(user)
        other_wallet = self._wallet_for(other_user)

        visible_tx = self._tx_log("emission_qr", wallet, actor_partner=user.partner_id)
        foreign_tx = self._tx_log(
            "emission_qr",
            other_wallet,
            actor_partner=user.partner_id,
            counterparty_partner=user.partner_id,
        )

        visible = self._response_data(self._call_transaction_detail(controller, visible_tx.id))
        self.assertEqual(visible["id"], visible_tx.id)
        self.assertEqual(visible["partner_id"], user.partner_id.id)

        refused = self._call_transaction_detail(controller, foreign_tx.id)
        self.assertFalse(refused.get("ok"))
        self.assertEqual(refused.get("error", {}).get("code"), "VALIDATION_ERROR")
