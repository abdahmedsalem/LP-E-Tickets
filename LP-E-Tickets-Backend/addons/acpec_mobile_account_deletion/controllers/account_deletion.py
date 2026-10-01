from odoo import http
from odoo.http import request
from odoo.addons.acpec_mobile_auth.controllers.api_common import AcpecMobileAuthApiCommon


class AccountDeletionApi(AcpecMobileAuthApiCommon):
    @http.route('/api/acpec/mobile_auth/v1/account-deletion/status',
                type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def deletion_status(self, **kwargs):
        try:
            session = self._get_mobile_session(required=True)
            model = request.env['acpec.mobile.account.deletion'].sudo()
            existing = model.search([('user_id', '=', session.user_id.id)], limit=1)
            return self._json_response({
                'request': existing._payload() if existing else None,
                'processing_days': None if existing else model._processing_days(),
            })
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/mobile_auth/v1/account-deletion/request',
                type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def deletion_request(self, **kwargs):
        try:
            if kwargs.get('confirmed') is not True:
                return self._error_response('CONFIRMATION_REQUIRED', 'Confirmation requise.')
            with self._sensitive_action_transaction(kwargs, purpose='account_deletion_request') as user:
                record = request.env['acpec.mobile.account.deletion']._request_for_user(user)
                result = record._payload()
            return self._json_response(result)
        except Exception as exc:
            return self._handle_exception_response(
                exc, params=kwargs, operation='account_deletion_request',
                endpoint='/api/acpec/mobile_auth/v1/account-deletion/request')
