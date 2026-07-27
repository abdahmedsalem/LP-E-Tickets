# -*- coding: utf-8 -*-
import ast
from pathlib import Path

from odoo import fields
from odoo.exceptions import AccessError
from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_mobile_auth.models import (
    mobile_session as mobile_session_module,
)


def _m23c8c_mobile_phone(label):
    value = 2166136261
    for char in str(label):
        value ^= ord(char)
        value = (value * 16777619) % 10000000
    return "3%07d" % value


@tagged("post_install", "-at_install")
class TestRefreshGraceDeviceBindingM23C8C(TransactionCase):

    def _group_ids(self):
        xmlids = (
            "base.group_portal",
            "acpec_mobile_auth.group_mobile_auth_user",
        )
        return [
            self.env.ref(xmlid).id
            for xmlid in xmlids
            if self.env.ref(xmlid, raise_if_not_found=False)
        ]

    def _create_mobile_user(self, label):
        email = "%s@example.com" % label
        phone = _m23c8c_mobile_phone(label)
        user_model = self.env["res.users"].sudo().with_context(
            acpec_mobile_allow_password_write=True,
            no_reset_password=True,
        )
        return user_model.create({
            "name": email,
            "login": phone,
            "mobile_phone": phone,
            "email": email,
            "active": True,
            "acpec_mobile_only": True,
            "acpec_mobile_state": "approved",
            "password": user_model._acpec_mobile_unusable_password(),
            "group_ids": [(6, 0, self._group_ids())],
        })

    def _set_grace_seconds(self, seconds=30):
        settings = self.env[
            "acpec.mobile.security.setting"
        ].sudo()
        key = "acpec_mobile_auth.refresh_token_grace_seconds"
        settings.search([("key", "=", key)]).unlink()
        settings.create({
            "key": key,
            "value": str(seconds),
            "active": True,
        })

    def _start_rotation(
        self,
        label,
        source_device_uid,
        successor_device_uid,
    ):
        self._set_grace_seconds(30)
        session_model = self.env[
            "acpec.mobile.session"
        ].sudo()
        user = self._create_mobile_user(label)
        first = session_model.create_for_user(user, {
            "device_uid": source_device_uid,
            "platform": "android",
        })
        second = session_model.refresh_with_token(
            first["refresh_token"],
            {
                "device_uid": successor_device_uid,
                "platform": "android",
            },
        )
        first["session"].invalidate_recordset([
            "state",
            "refresh_family_ref",
            "refresh_grace_used_at",
            "rotated_to_session_id",
        ])
        second["session"].invalidate_recordset([
            "state",
            "refresh_family_ref",
            "device_uid",
        ])
        return user, first, second

    def _refresh_expect_access_error_without_savepoint(
        self,
        refresh_token,
        device_vals,
    ):
        try:
            self.env[
                "acpec.mobile.session"
            ].sudo().refresh_with_token(
                refresh_token,
                device_vals,
            )
        except AccessError as exc:
            return exc
        self.fail("AccessError attendue.")

    def _assert_family_revoked(self, family_ref):
        family = self.env[
            "acpec.mobile.session"
        ].sudo().search([
            ("refresh_family_ref", "=", family_ref),
        ])
        self.assertTrue(family)
        family.invalidate_recordset(["state"])
        self.assertEqual(
            set(family.mapped("state")),
            {"revoked"},
        )
        return family

    def test_m23c8c_active_refresh_can_still_move_to_new_device(self):
        _, first, second = self._start_rotation(
            "m23c8c-active-migration",
            "ft-m23c8c-active-source",
            "ft-m23c8c-active-successor",
        )

        self.assertEqual(first["session"].state, "rotated")
        self.assertEqual(
            first["session"].rotated_to_session_id,
            second["session"],
        )
        self.assertEqual(
            second["session"].device_uid,
            "ft-m23c8c-active-successor",
        )
        self.assertEqual(
            second["session"].state,
            "active",
        )

    def test_m23c8c_grace_retry_same_successor_device_is_allowed(self):
        _, first, second = self._start_rotation(
            "m23c8c-grace-same",
            "ft-m23c8c-grace-same-source",
            "ft-m23c8c-grace-same-successor",
        )

        retry = self.env[
            "acpec.mobile.session"
        ].sudo().refresh_with_token(
            first["refresh_token"],
            {
                "device_uid": second["session"].device_uid,
                "platform": "android",
            },
        )

        first["session"].invalidate_recordset([
            "refresh_grace_used_at",
        ])
        retry["session"].invalidate_recordset([
            "state",
            "refresh_family_ref",
            "device_uid",
        ])

        self.assertTrue(
            first["session"].refresh_grace_used_at
        )
        self.assertEqual(
            retry["session"].device_uid,
            second["session"].device_uid,
        )
        self.assertEqual(
            retry["session"].refresh_family_ref,
            first["session"].refresh_family_ref,
        )
        self.assertEqual(
            retry["session"].state,
            "active",
        )

    def test_m23c8c_grace_retry_different_device_revokes_family(self):
        _, first, second = self._start_rotation(
            "m23c8c-grace-different",
            "ft-m23c8c-grace-different-source",
            "ft-m23c8c-grace-different-successor",
        )
        family_ref = first["session"].refresh_family_ref

        self._refresh_expect_access_error_without_savepoint(
            first["refresh_token"],
            {
                "device_uid": "ft-m23c8c-grace-attacker",
                "platform": "android",
            },
        )

        family = self._assert_family_revoked(family_ref)
        self.assertIn(first["session"], family)
        self.assertIn(second["session"], family)

    def test_m23c8c_grace_retry_missing_device_revokes_family(self):
        _, first, second = self._start_rotation(
            "m23c8c-grace-missing",
            "ft-m23c8c-grace-missing-source",
            "ft-m23c8c-grace-missing-successor",
        )
        family_ref = first["session"].refresh_family_ref

        self._refresh_expect_access_error_without_savepoint(
            first["refresh_token"],
            {},
        )

        family = self._assert_family_revoked(family_ref)
        self.assertIn(first["session"], family)
        self.assertIn(second["session"], family)

    def test_m23c8c_missing_first_successor_revokes_family(self):
        _, first, second = self._start_rotation(
            "m23c8c-successor-missing",
            "ft-m23c8c-successor-missing-source",
            "ft-m23c8c-successor-missing-device",
        )
        family_ref = first["session"].refresh_family_ref
        first["session"]._write_internal({
            "rotated_to_session_id": False,
        })

        self._refresh_expect_access_error_without_savepoint(
            first["refresh_token"],
            {
                "device_uid": second["session"].device_uid,
                "platform": "android",
            },
        )

        family = self._assert_family_revoked(family_ref)
        self.assertIn(first["session"], family)
        self.assertIn(second["session"], family)

    def test_m23c8c_non_active_first_successor_revokes_family(self):
        _, first, second = self._start_rotation(
            "m23c8c-successor-dead",
            "ft-m23c8c-successor-dead-source",
            "ft-m23c8c-successor-dead-device",
        )
        family_ref = first["session"].refresh_family_ref
        second["session"]._write_internal({
            "state": "revoked",
            "revoked_at": fields.Datetime.now(),
        })

        self._refresh_expect_access_error_without_savepoint(
            first["refresh_token"],
            {
                "device_uid": second["session"].device_uid,
                "platform": "android",
            },
        )

        self._assert_family_revoked(family_ref)

    def test_m23c8c_wrong_family_successor_revokes_only_source_family(self):
        user, first, second = self._start_rotation(
            "m23c8c-successor-family",
            "ft-m23c8c-successor-family-source",
            "ft-m23c8c-successor-family-device",
        )
        source_family_ref = (
            first["session"].refresh_family_ref
        )
        unrelated = self.env[
            "acpec.mobile.session"
        ].sudo().create_for_user(user, {
            "device_uid": "ft-m23c8c-unrelated-device",
            "platform": "android",
        })
        unrelated_family_ref = (
            unrelated["session"].refresh_family_ref
        )
        self.assertNotEqual(
            unrelated_family_ref,
            source_family_ref,
        )

        first["session"]._write_internal({
            "rotated_to_session_id": unrelated["session"].id,
        })

        self._refresh_expect_access_error_without_savepoint(
            first["refresh_token"],
            {
                "device_uid": unrelated["session"].device_uid,
                "platform": "android",
            },
        )

        family = self._assert_family_revoked(
            source_family_ref
        )
        self.assertIn(first["session"], family)
        self.assertIn(second["session"], family)

        unrelated["session"].invalidate_recordset(["state"])
        self.assertEqual(
            unrelated["session"].state,
            "active",
        )

    def test_m23c8c_runtime_source_contract_checks_grace_device(self):
        model_path = Path(
            mobile_session_module.__file__
        ).resolve()
        source = model_path.read_text(encoding="utf-8")
        tree = ast.parse(
            source,
            filename=str(model_path),
        )
        classes = [
            node
            for node in tree.body
            if (
                isinstance(node, ast.ClassDef)
                and node.name == "AcpecMobileSession"
            )
        ]
        self.assertEqual(len(classes), 1)

        methods = {
            node.name: node
            for node in classes[0].body
            if isinstance(node, ast.FunctionDef)
        }
        self.assertIn(
            "_assert_refresh_grace_device_binding",
            methods,
        )

        helper_source = ast.get_source_segment(
            source,
            methods[
                "_assert_refresh_grace_device_binding"
            ],
        )
        grace_source = ast.get_source_segment(
            source,
            methods[
                "_refresh_rotated_session_in_grace"
            ],
        )

        for marker in (
            "rotated_to_session_id",
            "refresh_family_ref",
            "device_uid",
            "_revoke_refresh_family",
            "refresh_replay_grace_device",
        ):
            self.assertIn(marker, helper_source)

        self.assertIn(
            "_assert_refresh_grace_device_binding",
            grace_source,
        )
        self.assertLess(
            grace_source.index(
                "_assert_refresh_grace_device_binding"
            ),
            grace_source.index(
                "'refresh_grace_used_at': now"
            ),
        )
        self.assertLess(
            grace_source.index(
                "_assert_refresh_grace_device_binding"
            ),
            grace_source.index(
                "_create_refresh_successor_session"
            ),
        )
