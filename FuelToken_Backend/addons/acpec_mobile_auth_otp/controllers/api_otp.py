from odoo import http, _, fields
from odoo.http import request
from odoo.exceptions import ValidationError

from odoo.addons.acpec_mobile_auth.controllers.api_common import AcpecMobileAuthApiCommon


class AcpecMobileAuthOtpApi(AcpecMobileAuthApiCommon):

    @http.route('/api/acpec/mobile_auth/v1/request-otp', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def request_otp(self, **kwargs):
        try:
            self._require_keys(kwargs, ['identifier'])
            identifier = self._get_clean_str(kwargs, 'identifier')
            purpose = self._get_clean_str(kwargs, 'purpose') or 'login'

            if purpose == 'register':
                identifier_vals = self._parse_signup_identifier(identifier)
                if identifier_vals['signup_identifier_type'] != 'phone':
                    raise ValidationError(_('Registration OTP currently supports phone numbers only.'))
                identifier = identifier_vals['phone']
                request.env['acpec.mobile.auth.otp'].sudo()._check_request_rate_limits(
                    identifier,
                    purpose='register',
                    request_ip=self._request_ip(),
                )

                existing_user = request.env['res.users'].sudo().with_context(active_test=False).search([
                    '|',
                    ('login', '=', identifier_vals['login']),
                    ('mobile_phone', '=', identifier_vals['phone']),
                ], limit=1)
                if existing_user:
                    return self._error_response(
                        'ACCOUNT_EXISTS',
                        _('A mobile account already exists for this identifier.')
                    )

            challenge, code = request.env['acpec.mobile.auth.otp'].sudo().request_otp(
                identifier,
                purpose=purpose,
                request_ip=self._request_ip(),
            )
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
            data['otp_challenge_id'] = data['challenge_id']
            data['otp_challenge_ref'] = data['challenge_ref']
            data['otp_expires_at'] = data['expires_at']
            data['otp_delivery'] = data['delivery']
            if 'dev_otp_code' in data:
                data['otp_dev_code'] = data['dev_otp_code']
            return self._json_response(data)
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/mobile_auth/v1/verify-otp', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
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
                name = self._get_clean_str(kwargs, 'name')
                secret_code = self._get_clean_str(kwargs, 'secret_code')
                email = self._get_clean_str(kwargs, 'email')
                note = self._get_clean_str(kwargs, 'note')
                company_id = self._get_optional_int(kwargs, 'company_id', False)
                if not name:
                    return self._error_response('NAME_REQUIRED', _('Name is required.'))
                if not secret_code:
                    return self._error_response('SECRET_CODE_REQUIRED', _('Secret code is required.'))

                company = self._get_company(company_id)
                identifier_vals = self._parse_signup_identifier(challenge.identifier or identifier)

                account_request = False
                if not user:
                    with request.env.cr.savepoint():
                        partner, user, account_request = self._create_mobile_signup_account(
                            name=name,
                            signup_identifier=identifier_vals['signup_identifier'],
                            secret_code=secret_code,
                            company=company,
                            email=email,
                            note=note,
                        )
                        challenge.sudo().write({'user_id': user.id})
                else:
                    account_request = request.env['acpec.mobile.auth.account.request'].sudo().search([
                        ('user_id', '=', user.id),
                        ('state', '=', 'pending'),
                    ], order='id desc', limit=1)

                # Registration OTP proves phone control, not administrative approval.
                # The user remains pending and receives no mobile session token here.
                user.sudo().write({
                    'active': True,
                    'mobile_state': 'pending',
                })

                payload = self._mobile_profile_payload(user)
                payload.update({
                    'auth_method': 'otp',
                    'pending_approval': True,
                    'account_request_id': account_request.id if account_request else False,
                    'message': 'Compte mobile créé. En attente d’approbation.',
                })
                return self._json_response(payload)
            payload = self._create_mobile_session_payload(user, kwargs)
            payload['auth_method'] = 'otp'
            return self._json_response(payload)
        except Exception as exc:
            return self._handle_exception_response(exc)
