# -*- coding: utf-8 -*-
import logging

from odoo import models
from odoo.http import request
from werkzeug.exceptions import Forbidden

_logger = logging.getLogger(__name__)


class IrHttp(models.AbstractModel):
    _inherit = "ir.http"

    @classmethod
    def _acpec_is_mobile_only_web_session(cls):
        """Return True only for a positive mobile_only web-session match.

        This method intentionally checks the Odoo web session principal, not
        mobile Bearer/custom authentication. Mobile API calls without an Odoo
        cookie session must not be impacted by this guard.
        """
        session = getattr(request, "session", None)
        session_uid = getattr(session, "uid", None)
        if not session_uid:
            return False

        env = getattr(request, "env", None)
        if not env or not getattr(env, "uid", None):
            return False

        user = env.user
        if not user or user._is_public():
            return False

        return bool(getattr(user, "acpec_mobile_only", False))

    @classmethod
    def _acpec_enforce_no_mobile_only_web_session(cls):
        """Deny mobile_only as Odoo web-session principal.

        This is a defense-in-depth guard. It must only block on a positive
        mobile_only match. If detection itself fails, fail open and log the
        exception, because this hook runs on every HTTP request.
        """
        try:
            is_mobile_only = cls._acpec_is_mobile_only_web_session()
        except Exception:
            _logger.exception("mobile_only web-session guard detection failed")
            return

        if not is_mobile_only:
            return

        session_uid = getattr(getattr(request, "session", None), "uid", None)
        path = getattr(getattr(request, "httprequest", None), "path", "?")
        _logger.warning(
            "Blocked web session for mobile_only user uid=%s on path=%s",
            session_uid,
            path,
        )

        request.session.logout(keep_db=True)
        raise Forbidden("Mobile-only users cannot use Odoo web sessions.")

    @classmethod
    def _authenticate(cls, endpoint):
        result = super()._authenticate(endpoint)
        cls._acpec_enforce_no_mobile_only_web_session()
        return result
