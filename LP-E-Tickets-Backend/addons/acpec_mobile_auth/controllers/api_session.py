from psycopg2 import errors as pg_errors

from odoo import http, _
from odoo.exceptions import AccessError
from odoo.http import request

from .api_common import AcpecMobileAuthApiCommon, MobileSessionClosedError


class AcpecMobileAuthApiSession(AcpecMobileAuthApiCommon):

    @http.route('/api/acpec/mobile_auth/v1/session-check', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def session_check(self, **kwargs):
        try:
            session = self._get_mobile_session(required=False)
            if session:
                return self._json_response(self._session_payload(session))
            if self._get_bearer_token():
                return self._error_response(
                    'SESSION_EXPIRED',
                    'Session mobile invalide ou expirée.',
                )
            return self._error_response('AUTH_REQUIRED', _('Authentification mobile requise.'))
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/mobile_auth/v1/me', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def me(self, **kwargs):
        try:
            session = self._get_mobile_session(required=True)
            return self._json_response(self._session_payload(session))
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/mobile_auth/v1/confirm-pin', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def confirm_pin(self, **kwargs):
        try:
            self._require_sensitive_action_pin(
                kwargs,
                purpose='session_unlock',
                log_allowed=True,
            )
            return self._json_response({'unlocked': True})
        except Exception as exc:
            return self._handle_exception_response(
                exc,
                params=kwargs,
                operation='confirm_pin',
                endpoint='/api/acpec/mobile_auth/v1/confirm-pin',
            )

    @http.route('/api/acpec/mobile_auth/v1/refresh', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def refresh(self, **kwargs):
        try:
            refresh_token = self._get_refresh_token(kwargs)
            if not refresh_token:
                return self._error_response(
                    'REFRESH_TOKEN_REQUIRED',
                    _('Refresh token requis.'),
                    action='LOGOUT_REQUIRED',
                )
            try:
                token_data = request.env['acpec.mobile.session'].sudo().refresh_with_token(
                    refresh_token,
                    self._session_device_values(kwargs),
                )
            except AccessError as exc:
                raise MobileSessionClosedError(debug_reason='refresh_session_closed') from exc
            session = token_data.pop('session')
            return self._json_response(self._session_payload(session, tokens=token_data))
        except (
            pg_errors.SerializationFailure,
            pg_errors.DeadlockDetected,
        ):
            raise
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/mobile_auth/v1/logout', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def logout(self, **kwargs):
        try:
            session = self._get_mobile_session(required=False)
            if session:
                session._revoke_for_mobile_logout()
            if not request.env.user._is_public():
                request.session.logout(keep_db=True)
            return self._json_response({'message': _('Logged out successfully.')})
        except Exception as exc:
            return self._handle_exception_response(exc)
