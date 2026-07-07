
from odoo import http, _
from odoo.exceptions import ValidationError
from odoo.http import request

from .api_common import AcpecMobileAuthApiCommon


class AcpecMobileAuthApiAdmin(AcpecMobileAuthApiCommon):

    @http.route('/api/acpec/mobile_auth/v1/admin/account-requests', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def admin_account_requests(self, **kwargs):
        try:
            user = self._mobile_manager_guard()

            state = self._get_clean_str(kwargs, 'state')
            limit = self._get_optional_int(kwargs, 'limit', 20)
            offset = self._get_optional_int(kwargs, 'offset', 0)

            if limit < 1:
                raise ValidationError(_('Limit must be greater than zero.'))
            if offset < 0:
                raise ValidationError(_('Offset must be greater than or equal to zero.'))

            self._validate_selection(state, 'state', ['pending', 'approved', 'rejected'])

            domain = self._company_domain_for_user(user)
            if state:
                domain.append(('state', '=', state))

            records = request.env['acpec.mobile.auth.account.request'].sudo().search(domain, order='id desc')
            items = records[offset:offset + limit]

            return self._json_response({
                'count': len(records),
                'items': [{
                    'id': rec.id,
                    'name': rec.name,
                    'name_display': rec.name_display,
                    'phone': rec.phone,
                    'state': rec.state,
                    'requested_at': rec.requested_at,
                    'reviewed_at': rec.reviewed_at,
                    'company_id': rec.company_id.id,
                    'company_name': rec.company_id.name,
                } for rec in items],
            })
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/mobile_auth/v1/admin/account-requests/<int:request_id>/approve', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def admin_approve_account_request(self, request_id, **kwargs):
        try:
            user = self._mobile_manager_guard()
            rec = self._get_account_request_or_404(request_id)
            if not rec:
                return self._error_response('ACCOUNT_REQUEST_NOT_FOUND', _('Account request not found.'))
            self._check_record_company_allowed(user, rec)

            with request.env.cr.savepoint():
                rec.action_approve()

            return self._json_response({
                'id': rec.id,
                'state': rec.state,
                'user_id': rec.user_id.id,
                'company_id': rec.company_id.id,
                'company_name': rec.company_id.name,
            })
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/mobile_auth/v1/admin/account-requests/<int:request_id>/reject', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def admin_reject_account_request(self, request_id, **kwargs):
        try:
            user = self._mobile_manager_guard()
            self._require_keys(kwargs, ['reason'])

            reason = self._get_clean_str(kwargs, 'reason')
            if not reason:
                raise ValidationError(_('Reason is required.'))

            rec = self._get_account_request_or_404(request_id)
            if not rec:
                return self._error_response('ACCOUNT_REQUEST_NOT_FOUND', _('Account request not found.'))
            self._check_record_company_allowed(user, rec)

            with request.env.cr.savepoint():
                rec.action_reject(reason=reason)

            return self._json_response({
                'id': rec.id,
                'state': rec.state,
            })
        except Exception as exc:
            return self._handle_exception_response(exc)
