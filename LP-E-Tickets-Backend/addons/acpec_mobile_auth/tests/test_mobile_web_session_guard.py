# -*- coding: utf-8 -*-
from types import SimpleNamespace
from unittest.mock import patch

from odoo.tests.common import TransactionCase, tagged
from werkzeug.exceptions import Forbidden

from odoo.addons.acpec_mobile_auth.models import mobile_web_session_guard as guard_module


class _FakeSession:
    def __init__(self, uid=None):
        self.uid = uid
        self.logged_out = False
        self.keep_db = None

    def logout(self, keep_db=True):
        self.logged_out = True
        self.keep_db = keep_db


class _FakeUser:
    def __init__(self, mobile_only=False, is_public=False, raise_on_public=False):
        self.acpec_mobile_only = mobile_only
        self._public = is_public
        self._raise_on_public = raise_on_public

    def _is_public(self):
        if self._raise_on_public:
            raise RuntimeError("simulated public-user detection failure")
        return self._public


@tagged("post_install", "-at_install")
class TestMobileWebSessionGuard(TransactionCase):

    def _make_request(self, *, session_uid, env_uid=None, user=None, path="/web"):
        if env_uid is None:
            env_uid = session_uid
        return SimpleNamespace(
            session=_FakeSession(uid=session_uid),
            env=SimpleNamespace(uid=env_uid, user=user or _FakeUser()),
            httprequest=SimpleNamespace(path=path),
        )

    def test_mobile_only_web_session_is_forbidden_and_logged_out(self):
        fake_request = self._make_request(
            session_uid=42,
            user=_FakeUser(mobile_only=True),
            path="/web",
        )

        with patch.object(guard_module, "request", fake_request):
            with self.assertRaises(Forbidden):
                self.env["ir.http"]._acpec_enforce_no_mobile_only_web_session()

        self.assertTrue(fake_request.session.logged_out)
        self.assertTrue(fake_request.session.keep_db)

    def test_mobile_only_public_route_with_cookie_is_also_forbidden(self):
        fake_request = self._make_request(
            session_uid=42,
            user=_FakeUser(mobile_only=True),
            path="/web/login",
        )

        with patch.object(guard_module, "request", fake_request):
            with self.assertRaises(Forbidden):
                self.env["ir.http"]._acpec_enforce_no_mobile_only_web_session()

        self.assertTrue(fake_request.session.logged_out)

    def test_regular_web_session_is_allowed(self):
        fake_request = self._make_request(
            session_uid=7,
            user=_FakeUser(mobile_only=False),
            path="/web",
        )

        with patch.object(guard_module, "request", fake_request):
            self.env["ir.http"]._acpec_enforce_no_mobile_only_web_session()

        self.assertFalse(fake_request.session.logged_out)

    def test_public_user_is_allowed(self):
        fake_request = self._make_request(
            session_uid=None,
            env_uid=None,
            user=_FakeUser(mobile_only=False, is_public=True),
            path="/web/login",
        )

        with patch.object(guard_module, "request", fake_request):
            self.env["ir.http"]._acpec_enforce_no_mobile_only_web_session()

        self.assertFalse(fake_request.session.logged_out)

    def test_mobile_api_without_odoo_cookie_session_is_not_blocked(self):
        """Bearer/custom mobile API calls must not be impacted by the web guard.

        The key condition is session.uid is None. Mobile authentication must
        continue to be handled by the mobile API layer, not by Odoo web cookies.
        """
        fake_request = self._make_request(
            session_uid=None,
            env_uid=None,
            user=_FakeUser(mobile_only=True),
            path="/api/mobile/session/refresh",
        )

        with patch.object(guard_module, "request", fake_request):
            self.env["ir.http"]._acpec_enforce_no_mobile_only_web_session()

        self.assertFalse(fake_request.session.logged_out)

    def test_detection_failure_is_fail_open(self):
        fake_request = self._make_request(
            session_uid=42,
            user=_FakeUser(mobile_only=True, raise_on_public=True),
            path="/web",
        )

        with (
            patch.object(guard_module, "request", fake_request),
            patch.object(guard_module._logger, "exception") as mocked_exception,
        ):
            self.env["ir.http"]._acpec_enforce_no_mobile_only_web_session()

        self.assertFalse(fake_request.session.logged_out)
        mocked_exception.assert_called_once()
