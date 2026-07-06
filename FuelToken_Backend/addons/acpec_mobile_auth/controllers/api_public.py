from odoo import http, _, fields
from odoo.http import request
from odoo.exceptions import AccessError

from .api_common import AcpecMobileAuthApiCommon, MobileSignupNotAllowedError



class AcpecMobileAuthApiPublic(AcpecMobileAuthApiCommon):

    @http.route('/api/acpec/mobile_auth/v1/version-check', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def version_check(self, **kwargs):
        try:
            self._require_keys(kwargs, ['platform', 'app_version'])

            platform = self._get_clean_str(kwargs, 'platform')
            app_version = self._get_clean_str(kwargs, 'app_version')
            build_number = self._get_optional_int(kwargs, 'build_number', False)

            self._validate_selection(platform, 'platform', ['android', 'ios'])

            data = request.env['acpec.mobile.app.version.policy'].sudo().evaluate_version(
                platform, app_version, build_number
            )
            return self._json_response(data)
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/mobile_auth/v1/signup-companies', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def signup_companies(self, **kwargs):
        try:
            return self._json_response({
                'items': self._get_signup_companies(),
            })
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/mobile_auth/v1/signup', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def signup(self, **kwargs):
        started_at = self._public_auth_started_at()
        try:
            self._require_keys(kwargs, ['name', 'signup_identifier', 'secret_code', 'company_id'])

            name = self._get_clean_str(kwargs, 'name')
            signup_identifier = self._get_clean_str(kwargs, 'signup_identifier')
            signup_identifier_type = self._get_clean_str(kwargs, 'signup_identifier_type')
            secret_code = self._get_clean_str(kwargs, 'secret_code')
            company_id = self._get_optional_int(kwargs, 'company_id', False)
            email = self._get_clean_str(kwargs, 'email')

            if not name:
                return self._error_response('NAME_REQUIRED', _('Name is required.'))

            identifier_vals = self._parse_signup_identifier(
                signup_identifier,
                signup_identifier_type=signup_identifier_type,
            )
            self._validate_secret_code(secret_code)
            try:
                company = self._get_company(company_id)
            except MobileSignupNotAllowedError as exc:
                return self._mobile_signup_not_allowed_response(
                    exc,
                    params=kwargs,
                    started_at=started_at,
                )

            if identifier_vals['signup_identifier_type'] == 'phone':
                request.env['acpec.mobile.auth.otp'].sudo()._check_request_rate_limits(
                    identifier_vals['phone'],
                    purpose='register',
                    request_ip=self._request_ip(),
                )

            user_domain = [('login', '=', identifier_vals['login'])]
            if identifier_vals['signup_identifier_type'] == 'phone':
                user_domain = ['|', ('login', '=', identifier_vals['login']), ('mobile_phone', '=', identifier_vals['phone'])]
            else:
                user_domain = ['|', ('login', '=', identifier_vals['login']), ('email', '=', identifier_vals['email'])]

            existing_user = request.env['res.users'].sudo().with_context(active_test=False).search(user_domain, limit=1)
            if existing_user:
                return self._mobile_signup_not_allowed_response(
                    params=kwargs,
                    company=company,
                    debug_reason='A mobile account already exists for this identifier.',
                    public_debug_reason='account_exists',
                    started_at=started_at,
                )

            data = {
                'name': name,
                'state': 'otp_required',
                'signup_identifier': identifier_vals['signup_identifier'],
                'signup_identifier_type': identifier_vals['signup_identifier_type'],
                'company_id': company.id,
                'company_name': company.name,
            }

            if identifier_vals['signup_identifier_type'] == 'phone':
                try:
                    challenge, code = request.env['acpec.mobile.auth.otp'].sudo().request_otp(
                        identifier_vals['phone'],
                        purpose='register',
                        request_ip=self._request_ip(),
                    )
                except AccessError as exc:
                    return self._mobile_signup_not_allowed_response(
                        params=kwargs,
                        company=company,
                        debug_reason=str(exc),
                        public_debug_reason=self._public_auth_debug_reason(exc),
                        started_at=started_at,
                    )
                data.update({
                    'otp_challenge_id': challenge.id,
                    'otp_challenge_ref': challenge.name,
                    'otp_expires_at': fields.Datetime.to_string(challenge.expires_at) if challenge.expires_at else False,
                    'otp_delivery': 'configured_provider',
                })
                if request.env['acpec.mobile.security.policy'].sudo().otp_dev_mode_enabled():
                    data['otp_delivery'] = 'dev_fixed_otp'
            else:
                return self._error_response(
                    'PHONE_REQUIRED',
                    _('Registration OTP currently supports phone numbers only.')
                )

            return self._json_response(data)
        except Exception as exc:
            return self._handle_exception_response(
                exc,
                params=kwargs,
                operation='signup',
                started_at=started_at,
            )

    @http.route([
        '/api/acpec/mobile_auth/v1/login',
        '/api/acpec/mobile_auth/v1/password-login',
    ], type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def password_login(self, **kwargs):
        # Password/PIN login is intentionally disabled.  Mobile login is OTP ->
        # Bearer tokens only; secret_code is a confirmation PIN stored separately
        # from res.users.password.
        return self._error_response(
            'PASSWORD_LOGIN_DISABLED',
            'L’authentification par mot de passe est désactivée. Utilisez l’OTP.',
        )
