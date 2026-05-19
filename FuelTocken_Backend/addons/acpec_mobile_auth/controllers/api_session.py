from odoo import http, _
from odoo.http import request

from .api_common import AcpecMobileAuthApiCommon


class AcpecMobileAuthApiSession(AcpecMobileAuthApiCommon):

    @http.route('/api/acpec/mobile_auth/v1/session-check', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def session_check(self, **kwargs):
        try:
            session = self._get_mobile_session(required=False)
            if session:
                return self._json_response(self._session_payload(session))
            user = request.env.user
            if not user._is_public():
                return self._json_response(self._mobile_profile_payload(user))
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

    @http.route('/api/acpec/mobile_auth/v1/refresh', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def refresh(self, **kwargs):
        try:
            refresh_token = self._get_refresh_token(kwargs)
            if not refresh_token:
                return self._error_response('REFRESH_TOKEN_REQUIRED', _('Refresh token requis.'))
            token_data = request.env['acpec.mobile.session'].sudo().refresh_with_token(
                refresh_token,
                self._session_device_values(kwargs),
            )
            session = token_data.pop('session')
            return self._json_response(self._session_payload(session, tokens=token_data))
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/mobile_auth/v1/logout', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def logout(self, **kwargs):
        try:
            session = self._get_mobile_session(required=False)
            if session:
                session.action_revoke()
            if not request.env.user._is_public():
                request.session.logout(keep_db=True)
            return self._json_response({'message': _('Logged out successfully.')})
        except Exception as exc:
            return self._handle_exception_response(exc)
