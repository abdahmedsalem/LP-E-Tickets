# -*- coding: utf-8 -*-
import ast
import inspect
from pathlib import Path
from unittest.mock import patch

from dateutil.relativedelta import relativedelta

from odoo import fields
from odoo.exceptions import AccessError
from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_mobile_auth.models import mobile_session as mobile_session_module


def _acpec_test_mobile_phone(label):
    value = 2166136261
    for char in str(label):
        value ^= ord(char)
        value = (value * 16777619) % 10000000
    return "3%07d" % value


@tagged("post_install", "-at_install")
class TestRefreshFamilyReplayM23C8B(TransactionCase):

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
        login = "%s@example.com" % label
        user_model = self.env["res.users"].sudo().with_context(
            acpec_mobile_allow_password_write=True,
            no_reset_password=True,
        )
        return user_model.create({
            "name": login,
            "login": _acpec_test_mobile_phone(login),
            "mobile_phone": _acpec_test_mobile_phone(login),
            "email": login,
            "active": True,
            "acpec_mobile_only": True,
            "acpec_mobile_state": "approved",
            "password": user_model._acpec_mobile_unusable_password(),
            "group_ids": [(6, 0, self._group_ids())],
        })

    def _set_grace_seconds(self, seconds):
        setting_model = self.env[
            "acpec.mobile.security.setting"
        ].sudo()
        key = "acpec_mobile_auth.refresh_token_grace_seconds"
        setting_model.search([("key", "=", key)]).unlink()
        setting_model.create({
            "key": key,
            "value": str(seconds),
            "active": True,
        })

    def _create_session(self, user, device_uid):
        return self.env[
            "acpec.mobile.session"
        ].sudo().create_for_user(user, {
            "device_uid": device_uid,
            "platform": "android",
        })

    def _refresh_expect_access_error_without_savepoint(
        self,
        refresh_token,
    ):
        # Le context manager d'assertion restaure son savepoint.
        # Ici, les écritures de révocation doivent rester visibles.
        try:
            self.env[
                "acpec.mobile.session"
            ].sudo().refresh_with_token(refresh_token)
        except AccessError as exc:
            return exc
        self.fail("AccessError attendue.")

    def _assert_family_field_contract(self):
        session_model = self.env["acpec.mobile.session"]

        self.assertIn(
            "refresh_family_ref",
            session_model._fields,
            "Le modèle doit porter une identité explicite de famille refresh.",
        )

        field = session_model._fields["refresh_family_ref"]

        self.assertTrue(field.required)
        self.assertTrue(field.readonly)
        self.assertFalse(field.copy)
        self.assertTrue(field.index)
        self.assertFalse(
            field.default,
            "La famille doit être fournie explicitement, sans default silencieux.",
        )

    def test_m23c8b_refresh_family_field_contract(self):
        self._assert_family_field_contract()

    def test_m23c8b_family_is_generated_and_propagated_to_all_successors(self):
        self._assert_family_field_contract()
        self._set_grace_seconds(30)

        user = self._create_mobile_user(
            "m23c8b-family-propagation"
        )
        first = self._create_session(
            user,
            "ft-device-m23c8b-family-a",
        )
        old_session = first["session"]

        second = self.env[
            "acpec.mobile.session"
        ].sudo().refresh_with_token(first["refresh_token"])

        retry = self.env[
            "acpec.mobile.session"
        ].sudo().refresh_with_token(first["refresh_token"])

        old_session.invalidate_recordset([
            "refresh_family_ref",
            "state",
        ])
        second["session"].invalidate_recordset([
            "refresh_family_ref",
            "state",
        ])
        retry["session"].invalidate_recordset([
            "refresh_family_ref",
            "state",
        ])

        family_ref = old_session.refresh_family_ref

        self.assertRegex(family_ref, r"^[0-9a-f]{32}$")
        self.assertEqual(
            second["session"].refresh_family_ref,
            family_ref,
        )
        self.assertEqual(
            retry["session"].refresh_family_ref,
            family_ref,
        )

        other_user = self._create_mobile_user(
            "m23c8b-family-other-user"
        )
        other = self._create_session(
            other_user,
            "ft-device-m23c8b-family-b",
        )

        self.assertRegex(
            other["session"].refresh_family_ref,
            r"^[0-9a-f]{32}$",
        )
        self.assertNotEqual(
            other["session"].refresh_family_ref,
            family_ref,
        )

    def test_m23c8b_consumed_grace_replay_revokes_full_family_only(self):
        self._assert_family_field_contract()
        self._set_grace_seconds(30)

        user = self._create_mobile_user(
            "m23c8b-consumed-grace"
        )
        first = self._create_session(
            user,
            "ft-device-m23c8b-consumed-a",
        )
        other = self._create_session(
            user,
            "ft-device-m23c8b-consumed-other",
        )

        second = self.env[
            "acpec.mobile.session"
        ].sudo().refresh_with_token(first["refresh_token"])

        retry = self.env[
            "acpec.mobile.session"
        ].sudo().refresh_with_token(first["refresh_token"])

        with patch.object(
            mobile_session_module._logger,
            "warning",
        ) as warning_mock:
            self._refresh_expect_access_error_without_savepoint(
                first["refresh_token"],
            )

        family = (
            first["session"]
            | second["session"]
            | retry["session"]
        )
        family.invalidate_recordset([
            "state",
            "revoked_at",
            "refresh_family_ref",
        ])
        other["session"].invalidate_recordset([
            "state",
            "refresh_family_ref",
        ])

        self.assertEqual(
            set(family.mapped("state")),
            {"revoked"},
        )
        self.assertTrue(
            all(family.mapped("revoked_at"))
        )
        self.assertEqual(other["session"].state, "active")
        self.assertNotEqual(
            other["session"].refresh_family_ref,
            first["session"].refresh_family_ref,
        )

        warning_calls = repr(warning_mock.call_args_list)

        self.assertIn(
            "mobile_session_family_revoked",
            warning_calls,
        )
        self.assertIn(
            "refresh_replay_grace_consumed",
            warning_calls,
        )
        self.assertNotIn(first["refresh_token"], warning_calls)
        self.assertNotIn(second["refresh_token"], warning_calls)
        self.assertNotIn(retry["refresh_token"], warning_calls)

    def test_m23c8b_expired_grace_replay_revokes_full_family(self):
        self._assert_family_field_contract()
        self._set_grace_seconds(30)

        user = self._create_mobile_user(
            "m23c8b-expired-grace"
        )
        first = self._create_session(
            user,
            "ft-device-m23c8b-expired-grace",
        )
        old_session = first["session"]

        second = self.env[
            "acpec.mobile.session"
        ].sudo().refresh_with_token(first["refresh_token"])

        old_session._write_internal({
            "refresh_grace_until": (
                fields.Datetime.now()
                - relativedelta(seconds=1)
            ),
        })

        self._refresh_expect_access_error_without_savepoint(
            first["refresh_token"],
        )

        family = old_session | second["session"]
        family.invalidate_recordset([
            "state",
            "revoked_at",
        ])

        self.assertEqual(
            set(family.mapped("state")),
            {"revoked"},
        )
        self.assertTrue(
            all(family.mapped("revoked_at"))
        )

    def test_m23c8b_dead_state_replay_revokes_live_family_members(self):
        self._assert_family_field_contract()
        self._set_grace_seconds(30)

        for dead_state in ("revoked", "expired"):
            with self.subTest(dead_state=dead_state):
                user = self._create_mobile_user(
                    "m23c8b-dead-%s" % dead_state
                )
                first = self._create_session(
                    user,
                    "ft-device-m23c8b-dead-%s"
                    % dead_state,
                )
                old_session = first["session"]

                second = self.env[
                    "acpec.mobile.session"
                ].sudo().refresh_with_token(
                    first["refresh_token"]
                )

                dead_values = {
                    "state": dead_state,
                }
                if dead_state == "revoked":
                    dead_values["revoked_at"] = (
                        fields.Datetime.now()
                    )

                old_session._write_internal(dead_values)

                self._refresh_expect_access_error_without_savepoint(
                    first["refresh_token"],
                )

                old_session.invalidate_recordset([
                    "state",
                ])
                second["session"].invalidate_recordset([
                    "state",
                    "revoked_at",
                ])

                self.assertEqual(
                    old_session.state,
                    dead_state,
                )
                self.assertEqual(
                    second["session"].state,
                    "revoked",
                )
                self.assertTrue(
                    second["session"].revoked_at
                )

    def test_m23c8b_unknown_refresh_token_has_no_collateral_effect(self):
        user = self._create_mobile_user(
            "m23c8b-unknown-token"
        )
        first = self._create_session(
            user,
            "ft-device-m23c8b-unknown-token",
        )

        with patch.object(
            mobile_session_module._logger,
            "warning",
        ) as warning_mock:
            with self.assertRaises(AccessError):
                self.env[
                    "acpec.mobile.session"
                ].sudo().refresh_with_token(
                    "unknown-refresh-token-m23c8b"
                )

        first["session"].invalidate_recordset([
            "state",
        ])

        self.assertEqual(
            first["session"].state,
            "active",
        )
        self.assertFalse(warning_mock.called)

    def test_m23c8b_refresh_family_is_immutable_after_creation(self):
        self._assert_family_field_contract()

        user = self._create_mobile_user(
            "m23c8b-family-immutable"
        )
        first = self._create_session(
            user,
            "ft-device-m23c8b-family-immutable",
        )
        session = first["session"]
        original_ref = session.refresh_family_ref

        with self.assertRaises(AccessError):
            session._write_internal({
                "refresh_family_ref": "f" * 32,
            })

        session.invalidate_recordset([
            "refresh_family_ref",
        ])

        self.assertEqual(
            session.refresh_family_ref,
            original_ref,
        )

    def test_m23c8b_runtime_source_contract_uses_lock_and_family_search(self):
        source_path = Path(
            inspect.getsourcefile(
                mobile_session_module.AcpecMobileSession
            )
        )
        source = source_path.read_text(encoding="utf-8")
        tree = ast.parse(
            source,
            filename=str(source_path),
        )

        model_classes = [
            node
            for node in tree.body
            if (
                isinstance(node, ast.ClassDef)
                and node.name == "AcpecMobileSession"
            )
        ]
        self.assertEqual(len(model_classes), 1)

        methods = {
            node.name: node
            for node in model_classes[0].body
            if isinstance(node, ast.FunctionDef)
        }

        self.assertIn(
            "_lock_refresh_session_for_update",
            methods,
        )
        self.assertIn(
            "_revoke_refresh_family",
            methods,
        )
        self.assertIn(
            "refresh_with_token",
            methods,
        )
        self.assertIn(
            "_new_refresh_family_ref",
            methods,
        )
        self.assertIn(
            "_assert_refreshable_mobile_session",
            methods,
        )

        for method_name in (
            "_new_refresh_family_ref",
            "_assert_refreshable_mobile_session",
        ):
            decorators = methods[method_name].decorator_list
            self.assertEqual(
                len(decorators),
                1,
                "%s doit avoir un seul décorateur."
                % method_name,
            )
            self.assertIsInstance(
                decorators[0],
                ast.Attribute,
            )
            self.assertEqual(
                decorators[0].attr,
                "model",
            )
            self.assertIsInstance(
                decorators[0].value,
                ast.Name,
            )
            self.assertEqual(
                decorators[0].value.id,
                "api",
            )

        lock_source = ast.get_source_segment(
            source,
            methods["_lock_refresh_session_for_update"],
        )
        revoke_source = ast.get_source_segment(
            source,
            methods["_revoke_refresh_family"],
        )
        refresh_source = ast.get_source_segment(
            source,
            methods["refresh_with_token"],
        )

        self.assertIn("FOR UPDATE", lock_source.upper())
        self.assertIn("refresh_token_hash", lock_source)
        self.assertIn("invalidate_recordset", lock_source)

        self.assertIn(
            "_lock_refresh_session_for_update",
            refresh_source,
        )

        self.assertIn("refresh_family_ref", revoke_source)
        self.assertIn("'active'", revoke_source)
        self.assertIn("'rotated'", revoke_source)
        self.assertIn("_write_internal", revoke_source)
        self.assertNotIn(
            "rotated_to_session_id",
            revoke_source,
        )

    def test_m23c8b_refresh_controller_re_raises_retryable_db_errors(self):
        controller_path = Path(
            mobile_session_module.__file__
        ).resolve().parents[1] / "controllers" / "api_session.py"
        source = controller_path.read_text(encoding="utf-8")
        tree = ast.parse(
            source,
            filename=str(controller_path),
        )

        controller_classes = [
            node
            for node in tree.body
            if (
                isinstance(node, ast.ClassDef)
                and node.name == "AcpecMobileAuthApiSession"
            )
        ]
        self.assertEqual(len(controller_classes), 1)

        refresh_methods = [
            node
            for node in controller_classes[0].body
            if (
                isinstance(node, ast.FunctionDef)
                and node.name == "refresh"
            )
        ]
        self.assertEqual(len(refresh_methods), 1)

        outer_tries = [
            node
            for node in refresh_methods[0].body
            if isinstance(node, ast.Try)
        ]
        self.assertEqual(len(outer_tries), 1)
        handlers = outer_tries[0].handlers
        self.assertEqual(len(handlers), 2)

        retry_handler = handlers[0]
        self.assertIsInstance(retry_handler.type, ast.Tuple)
        retry_names = {
            item.attr
            for item in retry_handler.type.elts
            if (
                isinstance(item, ast.Attribute)
                and isinstance(item.value, ast.Name)
                and item.value.id == "pg_errors"
            )
        }
        self.assertEqual(
            retry_names,
            {"SerializationFailure", "DeadlockDetected"},
        )
        self.assertEqual(len(retry_handler.body), 1)
        self.assertIsInstance(
            retry_handler.body[0],
            ast.Raise,
        )
        self.assertIsNone(retry_handler.body[0].exc)

        generic_handler = handlers[1]
        self.assertIsInstance(generic_handler.type, ast.Name)
        self.assertEqual(generic_handler.type.id, "Exception")
        generic_source = ast.get_source_segment(
            source,
            generic_handler,
        )
        self.assertIn(
            "_handle_exception_response",
            generic_source,
        )

    def test_m23c8b_refresh_family_reference_is_not_exposed_by_controllers(self):
        controller_root = Path(
            mobile_session_module.__file__
        ).resolve().parents[1] / "controllers"

        for path in sorted(controller_root.rglob("*.py")):
            source = path.read_text(encoding="utf-8")
            self.assertNotIn(
                "refresh_family_ref",
                source,
                "La référence interne de famille ne doit pas être exposée : %s"
                % path,
            )
