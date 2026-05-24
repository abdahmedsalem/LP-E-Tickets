import logging

from odoo import http, _, fields
from odoo.http import request

from .api_common import AcpecMobileAuthApiCommon

_logger = logging.getLogger(__name__)


class AcpecMobileAuthApiPublic(AcpecMobileAuthApiCommon):

    @http.route('/api/acpec/mobile_auth/v1/version-check', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def version_check(self, **kwargs):
        _logger.info("version_check: %s", kwargs)
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
        try:
            self._require_keys(kwargs, ['name', 'signup_identifier', 'secret_code', 'company_id'])

            name = self._get_clean_str(kwargs, 'name')
            signup_identifier = self._get_clean_str(kwargs, 'signup_identifier')
            secret_code = self._get_clean_str(kwargs, 'secret_code')
            company_id = self._get_optional_int(kwargs, 'company_id', False)
            note = kwargs.get('note')

            if not name:
                return self._error_response('NAME_REQUIRED', _('Name is required.'))

            identifier_vals = self._parse_signup_identifier(signup_identifier)
            self._validate_secret_code(secret_code)
            company = self._get_company(company_id)

            req_model = request.env['acpec.mobile.auth.account.request'].sudo()

            user_domain = [('login', '=', identifier_vals['login'])]
            if identifier_vals['signup_identifier_type'] == 'phone':
                user_domain = ['|', ('login', '=', identifier_vals['login']), ('mobile_phone', '=', identifier_vals['phone'])]
            else:
                user_domain = ['|', ('login', '=', identifier_vals['login']), ('email', '=', identifier_vals['email'])]

            existing_user = request.env['res.users'].sudo().search(user_domain, limit=1)
            if existing_user:
                return self._error_response(
                    'ACCOUNT_EXISTS',
                    _('A mobile account already exists for this identifier.')
                )

            if req_model.search([('signup_identifier', '=', identifier_vals['signup_identifier']), ('state', '=', 'pending')], limit=1):
                return self._error_response(
                    'ACCOUNT_REQUEST_EXISTS',
                    _('A pending account request already exists for this identifier.')
                )

            with request.env.cr.savepoint():
                partner_vals = {
                    'name': name,
                    'company_id': company.id,
                }
                if identifier_vals['phone']:
                    partner_vals['phone'] = '+222' + identifier_vals['phone']
                if identifier_vals['email']:
                    partner_vals['email'] = identifier_vals['email']
                partner = request.env['res.partner'].sudo().create(partner_vals)

                user_vals = {
                    'name': name,
                    'login': identifier_vals['login'],
                    'partner_id': partner.id,
                    'company_id': company.id,
                    'company_ids': [(6, 0, [company.id])],
                    'active': False,
                    'mobile_state': 'pending',
                    'password': secret_code,
                }
                if identifier_vals['phone']:
                    user_vals['mobile_phone'] = identifier_vals['phone']
                if identifier_vals['email']:
                    user_vals['email'] = identifier_vals['email']

                user = request.env['res.users'].sudo().with_context(no_reset_password=True).create(user_vals)

                record = req_model.create({
                    'name_display': name,
                    'signup_identifier': identifier_vals['signup_identifier'],
                    'signup_identifier_type': identifier_vals['signup_identifier_type'],
                    'phone': identifier_vals['phone'] or False,
                    'email': identifier_vals['email'] or False,
                    'login': identifier_vals['login'],
                    'company_id': company.id,
                    'partner_id': partner.id,
                    'user_id': user.id,
                    'note': note or False,
                })

            return self._json_response({
                'account_request_id': record.id,
                'name': name,
                'state': record.state,
                'signup_identifier': record.signup_identifier,
                'signup_identifier_type': record.signup_identifier_type,
                'company_id': company.id,
                'company_name': company.name,
            })
        except Exception as exc:
            _logger.exception("Signup API Error")
            return self._handle_exception_response(exc)

    @http.route([
        '/api/acpec/mobile_auth/v1/login',
        '/api/acpec/mobile_auth/v1/password-login',
    ], type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def password_login(self, **kwargs):
        try:
            if not self._get_config_bool('acpec_mobile_auth.allow_password_login', default=False):
                return self._error_response(
                    'PASSWORD_LOGIN_DISABLED',
                    _('L’authentification par mot de passe est désactivée.')
                )

            self._require_keys(kwargs, ['identifier', 'secret_code'])

            identifier = self._get_clean_str(kwargs, 'identifier')
            secret_code = self._get_clean_str(kwargs, 'secret_code')

            if not identifier:
                return self._error_response('IDENTIFIER_REQUIRED', _('Identifier is required.'))

            self._validate_secret_code(secret_code)

            credential = {
                'login': identifier,
                'password': secret_code,
                'type': 'password'
            }

            try:
                auth_info = request.session.authenticate(request.env, credential)
                uid = auth_info.get('uid')
            except Exception:
                uid = False

            if not uid:
                return self._error_response('INVALID_CREDENTIALS', _('Invalid identifier or secret code.'))

            user = request.env['res.users'].sudo().browse(uid)

            if self._requires_mobile_approval(user) and user.mobile_state != 'approved':
                request.session.logout(keep_db=True)
                return self._error_response('ACCOUNT_NOT_APPROVED', _('Your account is not yet approved.'))

            with request.env.cr.savepoint():
                user.write({
                    'mobile_pin_set_at': user.mobile_pin_set_at or fields.Datetime.now()
                })
                payload = self._create_mobile_session_payload(user, kwargs)
                payload['auth_method'] = 'password_dev'

            # The mobile API must not rely on the Odoo web session.
            # /login is kept only as a compatibility alias for the mobile password login.
            request.session.logout(keep_db=True)
            return self._json_response(payload)
        except Exception as exc:
            _logger.exception("Password Login API Error")
            return self._handle_exception_response(exc)
