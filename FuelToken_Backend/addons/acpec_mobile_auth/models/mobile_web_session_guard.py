# -*- coding: utf-8 -*-
import logging

from odoo import models
from odoo.http import request
from werkzeug.exceptions import Forbidden

_logger = logging.getLogger(__name__)


class IrHttp(models.AbstractModel):
    _inherit = "ir.http"

    @classmethod
    def _acpec_mark_mobile_api_route(cls, endpoint):
        """Remember a matched ACPEC JSON-RPC route on the current request.

        The final error boundary must never guess from the URL alone: a JSON
        request to an unknown /api/acpec/... path is still a normal Odoo 404.
        Marking happens only after routing and authentication succeeded.
        """
        path = getattr(getattr(request, "httprequest", None), "path", "") or ""
        routing = getattr(endpoint, "routing", {}) or {}
        matched = (
            path.startswith("/api/acpec/")
            and routing.get("type") == "jsonrpc"
        )
        request._acpec_mobile_api_route_matched = bool(matched)
        request._acpec_mobile_api_operation = (
            getattr(endpoint, "__name__", False) if matched else False
        )
        return bool(matched)

    @classmethod
    def _acpec_should_handle_final_mobile_api_error(cls):
        dispatcher = getattr(request, "dispatcher", None)
        return bool(
            getattr(request, "_acpec_mobile_api_route_matched", False)
            and getattr(dispatcher, "routing_type", None) == "jsonrpc"
        )

    @classmethod
    def _acpec_handle_final_mobile_api_error(cls, exception):
        """Return the standard ACPEC payload for an uncaught API exception.

        This runs after Odoo's request retry layer. Retryable concurrency
        exceptions must therefore be converted here instead of being raised
        again. The shared controller helper keeps the public payload, log
        redaction and committed ERR marker identical to controller wrappers.
        """
        from odoo.addons.acpec_mobile_auth.controllers.api_common import (
            AcpecMobileAuthApiCommon,
        )

        controller = AcpecMobileAuthApiCommon()
        payload = controller._handle_exception_response(
            exception,
            params=getattr(request, "params", {}) or {},
            operation=getattr(
                request,
                "_acpec_mobile_api_operation",
                False,
            ),
            endpoint=getattr(
                getattr(request, "httprequest", None),
                "path",
                False,
            ),
            allow_odoo_concurrency_retry=False,
        )
        return request.dispatcher._response(result=payload)

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
        cls._acpec_mark_mobile_api_route(endpoint)
        return result

    @classmethod
    def _handle_error(cls, exception):
        if not cls._acpec_should_handle_final_mobile_api_error():
            return super()._handle_error(exception)

        try:
            return cls._acpec_handle_final_mobile_api_error(exception)
        except Exception:
            _logger.exception(
                "ACPEC mobile API final error boundary failed path=%s",
                getattr(getattr(request, "httprequest", None), "path", "?"),
            )
            return super()._handle_error(exception)
