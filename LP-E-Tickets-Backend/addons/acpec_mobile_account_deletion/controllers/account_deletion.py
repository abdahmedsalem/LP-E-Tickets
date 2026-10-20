from odoo import http
from odoo.http import request
from odoo.addons.acpec_mobile_auth.controllers.api_common import AcpecMobileAuthApiCommon


class AccountDeletionApi(AcpecMobileAuthApiCommon):
    @http.route('/api/acpec/mobile_auth/v1/account-deletion/status',
                type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def deletion_status(self, **kwargs):
        try:
            session = self._get_mobile_session(required=True)
            model = self._api_env()['acpec.mobile.account.deletion'].sudo()
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
                record = self._api_env()['acpec.mobile.account.deletion']._request_for_user(user)
                result = record._payload()
            return self._json_response(result)
        except Exception as exc:
            return self._handle_exception_response(
                exc, params=kwargs, operation='account_deletion_request',
                endpoint='/api/acpec/mobile_auth/v1/account-deletion/request')

    @http.route('/api/acpec/mobile_auth/v1/account-deletion/preview',
                type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def deletion_preview(self, **kwargs):
        try:
            user = self._require_mobile_auth()
            return self._json_response(self._api_env()['acpec.mobile.account.deletion'].sudo()._wallet_report(user))
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/mobile_auth/v1/account-deletion/recover',
                type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def deletion_recover(self, **kwargs):
        try:
            # Opaque high-entropy receipt: no login, account identifier or PII returned.
            return self._json_response(self._api_env()['acpec.mobile.account.deletion'].sudo()._recover_immediate(
                kwargs.get('recovery_key')))
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/mobile_auth/v1/account-deletion/execute',
                type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def deletion_execute(self, **kwargs):
        try:
            model = self._api_env()['acpec.mobile.account.deletion'].sudo()
            recovered = model._recover_immediate(kwargs.get('recovery_key'))
            if recovered['completed']:
                return self._json_response(recovered)
            if kwargs.get('confirmed') is not True:
                return self._error_response('CONFIRMATION_REQUIRED', 'Confirmation requise.')
            # Same PIN validation and success-audit invariant as
            # _sensitive_action_transaction; scrub the audit before inserting it
            # because erasure also purges the old session/device records.
            user, audit = self._require_sensitive_action_pin(
                kwargs, purpose='account_deletion_execute', log_allowed=False, return_audit_vals=True, require_trusted_device=False)
            with self._api_env().cr.savepoint():
                result = model._delete_immediately(user, kwargs.get('snapshot'),
                                                  kwargs.get('waive_value'), kwargs.get('recovery_key'))
                audit.update({'session_id': False, 'device_uid': False, 'device_name': False,
                              'ip_address': False, 'user_agent': False, 'debug_reason': False,
                              'idempotency_key': False})
                self._audit_in_transaction(audit)
                model._scrub_deletion_audit(user)
            return self._json_response(result)
        except Exception as exc:
            return self._handle_exception_response(
                exc, params={'confirmed': kwargs.get('confirmed')},
                operation='account_deletion_execute',
                endpoint='/api/acpec/mobile_auth/v1/account-deletion/execute')
