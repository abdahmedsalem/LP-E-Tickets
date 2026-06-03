from odoo import http, _, fields
from odoo.http import request
from odoo.exceptions import ValidationError

from odoo.addons.acpec_mobile_auth.controllers.api_common import AcpecMobileAuthApiCommon


class AcpecMobileAuthOtpApi(AcpecMobileAuthApiCommon):

    @http.route('/api/acpec/mobile_auth/v1/request-otp', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def request_otp(self, **kwargs):
        try:
            self._require_keys(kwargs, ['identifier'])
            identifier = self._get_clean_str(kwargs, 'identifier')
            purpose = self._get_clean_str(kwargs, 'purpose') or 'login'
            challenge, code = request.env['acpec.mobile.auth.otp'].sudo().request_otp(identifier, purpose=purpose)
            data = {
                'challenge_id': challenge.id,
                'challenge_ref': challenge.name,
                'identifier': challenge.identifier,
                'purpose': challenge.purpose,
                'expires_at': fields.Datetime.to_string(challenge.expires_at) if challenge.expires_at else False,
                'delivery': 'configured_provider',
            }
            if self._get_config_bool('acpec_mobile_auth.otp_dev_mode', default=False):
                data['dev_otp_code'] = code
                data['delivery'] = 'dev_response'
            return self._json_response(data)
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/mobile_auth/v1/verify-otp', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def verify_otp(self, **kwargs):
        try:
            self._require_keys(kwargs, ['code'])
            challenge_id = self._get_optional_int(kwargs, 'challenge_id', 0)
            identifier = self._get_clean_str(kwargs, 'identifier')
            code = self._get_clean_str(kwargs, 'code')
            domain = [('state', '=', 'pending')]
            if challenge_id:
                domain.append(('id', '=', challenge_id))
            elif identifier:
                domain.append(('identifier', '=', identifier))
            else:
                raise ValidationError(_('challenge_id ou identifier est requis.'))
            challenge = request.env['acpec.mobile.auth.otp'].sudo().search(domain, order='id desc', limit=1)
            if not challenge:
                return self._error_response('OTP_NOT_FOUND', _('Challenge OTP introuvable.'))
            user = challenge.verify(code)
            if challenge.purpose == 'register':
                now = fields.Datetime.now()
                user.sudo().write({
                    'active': True,
                    'mobile_state': 'approved',
                    'mobile_pin_set_at': user.mobile_pin_set_at or now,
                })
                account_request = request.env['acpec.mobile.auth.account.request'].sudo().search([
                    ('user_id', '=', user.id),
                ], order='id desc', limit=1)
                if account_request and account_request.state == 'pending':
                    account_request.write({
                        'state': 'approved',
                        'reviewed_at': now,
                        'reviewed_by': request.env.user.id,
                    })
            payload = self._create_mobile_session_payload(user, kwargs)
            payload['auth_method'] = 'otp'
            return self._json_response(payload)
        except Exception as exc:
            return self._handle_exception_response(exc)
