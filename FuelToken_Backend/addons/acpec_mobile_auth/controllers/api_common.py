import hashlib
import logging
import re

from odoo import http, _, fields
from odoo.exceptions import AccessError, ValidationError

from odoo.addons.acpec_mobile_auth.exceptions import MobileAuthRateLimitError
from odoo.http import request

_logger = logging.getLogger(__name__)


class AcpecMobileAuthApiCommon(http.Controller):

    EMAIL_RE = re.compile(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')


    def _api_env(self):
        test_env = getattr(self, '_test_env', None)
        if test_env:
            return test_env
        return request.env

    def _json_response(self, data=None, ok=True):
        """Backward compatible API response.

        The former mobile API returned {ok, data}.  The new Flutter/Odoo
        contract can also consume {success, data}.  Keeping both avoids a
        hard mobile cutover while the app is being migrated away from Django.
        """
        return {
            'ok': ok,
            'success': ok,
            'data': data or {},
        }

    def _error_response(self, code, message, details=False):
        payload = {
            'ok': False,
            'success': False,
            'error': {
                'code': code,
                'message': message,
            }
        }
        if details:
            payload['error']['details'] = details
        return payload

    def _handle_exception_response(self, exc):
        if isinstance(exc, MobileAuthRateLimitError):
            _logger.warning(str(exc))
            return self._error_response('RATE_LIMITED', str(exc))
        if isinstance(exc, ValidationError):
            _logger.warning(str(exc))
            return self._error_response('VALIDATION_ERROR', str(exc))
        if isinstance(exc, AccessError):
            _logger.warning(str(exc))
            return self._error_response('ACCESS_ERROR', str(exc))
        _logger.exception('Unhandled API error')
        return self._error_response(
            'SERVER_ERROR',
            str(exc) or _('An unexpected server error occurred.'),
        )

    def _require_keys(self, params, required_keys):
        missing_keys = [key for key in required_keys if key not in params]
        if missing_keys:
            raise ValidationError(
                _("Missing required parameter(s): %s") % ", ".join(missing_keys)
            )

    def _get_clean_str(self, params, key):
        value = params.get(key)
        return (str(value) if value not in (False, None) else '').strip()

    def _get_optional_int(self, params, key, default=False):
        value = params.get(key, default)
        if value in (False, None, ''):
            return default
        try:
            return int(value)
        except (ValueError, TypeError):
            raise ValidationError(
                _("Parameter '%s' must be an integer.") % key
            )

    def _get_optional_float(self, params, key, default=False):
        value = params.get(key, default)
        if value in (False, None, ''):
            return default
        try:
            return float(value)
        except (ValueError, TypeError):
            raise ValidationError(
                _("Parameter '%s' must be a number.") % key
            )

    def _get_bool_param(self, value, default=False):
        if value in (False, None, ''):
            return default
        if isinstance(value, bool):
            return value
        return str(value).strip().lower() in ('1', 'true', 'yes', 'y', 'oui')

    def _request_ip(self):
        """Return the client IP when an HTTP request is bound.

        Unit tests may call controller methods directly, outside Odoo's
        request-local context.  In that case werkzeug raises RuntimeError
        when resolving the request proxy; returning an empty IP keeps the
        public API helpers testable without weakening runtime behaviour.
        """
        try:
            httprequest = getattr(request, 'httprequest', None)
        except RuntimeError:
            return ''
        return (getattr(httprequest, 'remote_addr', '') or '').strip()

    def _get_config_bool(self, key, default=False):
        value = request.env['ir.config_parameter'].sudo().get_param(key)
        if value in (False, None, ''):
            return default
        return self._get_bool_param(value, default=default)

    def _get_config_int(self, key, default=0):
        value = request.env['ir.config_parameter'].sudo().get_param(key)
        if value in (False, None, ''):
            return default
        try:
            return int(value)
        except Exception:
            return default

    def _validate_selection(self, value, key, allowed_values):
        if value and value not in allowed_values:
            raise ValidationError(
                _("Invalid value for '%s'. Allowed values: %s") % (
                    key, ", ".join(allowed_values)
                )
            )

    def _mobile_manager_guard(self):
        """Guard for JSON-RPC mobile admin/manager routes.

        Mobile API routes must authenticate exclusively with a mobile Bearer
        token from Authorization or X-ACPEC-Mobile-Token. They must never fall
        back to request.env.user: an Odoo backend cookie must not grant access
        to auth='public' mobile endpoints.

        Back-office Odoo routes must use auth='user' and their own explicit
        internal-user group checks instead of this mobile API guard.
        """
        user = self._require_mobile_auth()
        self._require_fuel_group(user, 'manager')
        return user.sudo()


    def _allowed_company_ids_for_user(self, user):
        """Return company ids explicitly allowed for a mobile API user."""
        company_ids = user.company_ids.ids
        if not company_ids and user.company_id:
            company_ids = [user.company_id.id]
        return company_ids

    def _company_domain_for_user(self, user, field_name='company_id'):
        """Return a domain restricting records to the user's allowed companies."""
        return [(field_name, 'in', self._allowed_company_ids_for_user(user))]

    def _require_allowed_company(self, user, company_id=False):
        """Return a company only if it belongs to the mobile user's scope."""
        target_company_id = company_id or (user.company_id.id if user.company_id else False)
        company = self._api_env()['res.company'].sudo().browse(target_company_id).exists()
        if not company:
            raise ValidationError(_('Société introuvable.'))
        if company.id not in self._allowed_company_ids_for_user(user):
            raise AccessError('Société non autorisée pour cet utilisateur mobile.')
        return company

    def _check_record_company_allowed(self, user, record, field_name='company_id'):
        """Raise if a sudo-browsed record is outside the mobile user's company scope."""
        if not record:
            return record
        company = record[field_name]
        if company and company.id not in self._allowed_company_ids_for_user(user):
            raise AccessError('Accès refusé : société non autorisée.')
        return record

    def _require_user_company_membership(self, target_user, company):
        """Ensure a target user can be linked to a record of the given company."""
        if not target_user:
            raise ValidationError(_('Utilisateur introuvable.'))
        if company not in target_user.company_ids:
            raise ValidationError('L’utilisateur doit appartenir à la société sélectionnée.')
        return target_user

    def _admin_guard(self):
        """Backward-compatible alias for mobile admin routes.

        Kept only to avoid reintroducing the former hybrid cookie/Bearer
        behavior. New mobile API code should call _mobile_manager_guard().
        """
        return self._mobile_manager_guard()

    def _get_company(self, company_id=False):
        company = request.env['res.company'].sudo().browse(
            company_id or request.env.company.id
        ).exists()
        if not company:
            raise ValidationError(_('Company not found.'))
        if not company.acpec_mobile_auth_enabled:
            raise ValidationError(_('This company does not accept mobile application registration.'))
        return company

    def _validate_secret_code(self, secret_code):
        if not secret_code or not secret_code.isdigit() or len(secret_code) != 4:
            raise ValidationError(_('The secret code must contain exactly 4 digits.'))

    def _get_account_request_or_404(self, request_id):
        rec = request.env['acpec.mobile.auth.account.request'].sudo().browse(request_id).exists()
        return rec if rec else False

    def _validate_phone_number(self, phone_number):
        if not (len(phone_number) == 8 and phone_number[0] in ['2', '3', '4'] and phone_number.isdigit()):
            raise ValidationError(
                _('The phone number must contain 8 digits and start with 2, 3, or 4.')
            )

    def _validate_email(self, email):
        if not self.EMAIL_RE.match(email or ''):
            raise ValidationError(_('Invalid email address.'))

    def _parse_signup_identifier(self, signup_identifier):
        identifier = (signup_identifier or '').strip()
        if not identifier:
            raise ValidationError(_('Signup identifier is required.'))

        if '@' in identifier:
            email = identifier.lower()
            self._validate_email(email)
            return {
                'signup_identifier': email,
                'signup_identifier_type': 'email',
                'login': email,
                'phone': False,
                'email': email,
            }

        phone_identifier = re.sub(r'\D', '', identifier)
        if phone_identifier.startswith('222') and len(phone_identifier) == 11:
            phone_identifier = phone_identifier[3:]
        self._validate_phone_number(phone_identifier)
        return {
            'signup_identifier': phone_identifier,
            'signup_identifier_type': 'phone',
            'login': phone_identifier,
            'phone': phone_identifier,
            'email': False,
        }

    def _mobile_signup_group_ids(self):
        """Return the groups assigned to accounts created by the mobile OTP flow.

        Mobile FuelToken users are mobile-only identities. They must not
        receive Odoo's portal or public website groups; their access is driven
        only by the mobile authentication/session layer and FuelToken mobile
        application groups.
        """
        group_ids = []
        for xmlid in (
            'acpec_mobile_auth.group_mobile_auth_user',
            'acpec_fueltoken_base.group_fuel_user',
        ):
            group = request.env.ref(xmlid, raise_if_not_found=False)
            if group:
                group_ids.append(group.id)
        return group_ids

    def _create_mobile_signup_account(self, *, name, signup_identifier, secret_code, company, email=False, note=False):
        identifier_vals = self._parse_signup_identifier(signup_identifier)
        self._validate_secret_code(secret_code)

        user_model = request.env['res.users'].sudo().with_context(active_test=False)

        user_domain = [('login', '=', identifier_vals['login'])]
        if identifier_vals['signup_identifier_type'] == 'phone':
            user_domain = ['|', ('login', '=', identifier_vals['login']), ('mobile_phone', '=', identifier_vals['phone'])]
        else:
            user_domain = ['|', ('login', '=', identifier_vals['login']), ('email', '=', identifier_vals['email'])]

        existing_user = user_model.search(user_domain, limit=1)
        if existing_user:
            raise ValidationError(_('A mobile account already exists for this identifier.'))

        partner_vals = {
            'name': name,
            'company_id': company.id,
        }
        if identifier_vals['phone']:
            partner_vals['phone'] = '+222' + identifier_vals['phone']
        email_value = (email or identifier_vals['email'] or '').strip()
        if email_value:
            partner_vals['email'] = email_value

        partner = request.env['res.partner'].sudo().create(partner_vals)

        mobile_group_ids = self._mobile_signup_group_ids()

        user_vals = {
            'name': name,
            'login': identifier_vals['login'],
            'partner_id': partner.id,
            'company_id': company.id,
            'company_ids': [(6, 0, [company.id])],
            'active': True,
            'mobile_state': 'approved',
            'password': user_model._acpec_mobile_unusable_password(),
        }
        if mobile_group_ids:
            user_vals['group_ids'] = [(6, 0, mobile_group_ids)]
        if identifier_vals['phone']:
            user_vals['mobile_phone'] = identifier_vals['phone']
        if email_value:
            user_vals['email'] = email_value

        user = request.env['res.users'].sudo().with_context(no_reset_password=True).create(user_vals)
        user.set_mobile_pin(secret_code)
        return False, user, identifier_vals

    def _get_signup_companies(self):
        companies = request.env['res.company'].sudo().search([
            ('acpec_mobile_auth_enabled', '=', True)
        ], order='name')
        return [{
            'id': company.id,
            'name': company.name,
        } for company in companies]

    def _has_group_safe(self, user, xmlid):
        try:
            return user.has_group(xmlid)
        except Exception:
            return False

    def _get_mobile_profile(self, user):
        # Mobile profiles are intentionally limited to the mobile/API groups.
        # group_fuel_admin is reserved for the Odoo back-office and must not be
        # interpreted as an application mobile role.
        if self._has_group_safe(user, 'acpec_fueltoken_base.group_fuel_manager'):
            return 'manager'
        if self._has_group_safe(user, 'acpec_fueltoken_base.group_fuel_station'):
            return 'station'
        return 'user'

    def _requires_mobile_approval(self, user):
        if self._has_group_safe(user, 'acpec_fueltoken_base.group_fuel_station'):
            return False
        if 'acpec.fuel.station' not in request.env.registry:
            return True
        station = request.env['acpec.fuel.station'].sudo().search([
            ('user_id', '=', user.id),
            ('active', '=', True),
        ], limit=1)
        return not bool(station)

    def _normalize_bearer_token(self, token=False):
        token = (token or '').strip()
        if token.lower().startswith('bearer '):
            token = token[7:].strip()
        return token

    def _get_bearer_token(self):
        header = request.httprequest.headers.get('Authorization') or ''
        token = self._normalize_bearer_token(header)
        if not token:
            token = self._normalize_bearer_token(request.httprequest.headers.get('X-ACPEC-Mobile-Token') or '')
        return token

    def _get_refresh_token(self, params=None):
        params = params or {}
        token = self._get_clean_str(params, 'refresh_token') if params else ''
        if not token:
            token = self._normalize_bearer_token(request.httprequest.headers.get('X-ACPEC-Refresh-Token') or '')
        return token

    def _get_mobile_session(self, required=True):
        token = self._get_bearer_token()
        if not token:
            if required:
                raise AccessError(_('Authentification mobile requise.'))
            return request.env['acpec.mobile.session']
        session = request.env['acpec.mobile.session'].sudo().authenticate_access_token(token)
        if not session:
            if required:
                raise AccessError(_('Session mobile invalide ou expirée.'))
            return request.env['acpec.mobile.session']
        return session

    def _assert_mobile_only_user(self, user):
        if not user or not user.exists() or not user.active:
            raise AccessError(_('Utilisateur mobile invalide ou inactif.'))
        forbidden_xmlids = (
            'base.group_user',
            'base.group_portal',
            'acpec_fueltoken_base.group_fuel_admin',
        )
        for xmlid in forbidden_xmlids:
            if self._has_group_safe(user, xmlid):
                raise AccessError(_('Ce compte n’est pas autorisé à utiliser l’application mobile FuelToken.'))

    def _require_mobile_auth(self):
        session = self._get_mobile_session(required=True)
        user = session.user_id.sudo()
        self._assert_mobile_only_user(user)
        return user

    def _mobile_profile_payload(self, user, session=False):
        data = {
            'uid': user.id,
            'name': user.name,
            'login': user.login,
            'partner_id': user.partner_id.id,
            'mobile_phone': user.mobile_phone,
            'email': user.email,
            'mobile_state': user.mobile_state,
            'mobile_pin_set': bool(user.mobile_pin_set),
            'mobile_pin_required': bool(user.mobile_pin_required),
            'profile': self._get_mobile_profile(user),
            'company_id': user.company_id.id,
            'company_name': user.company_id.name,
        }
        if session:
            data.update({
                'session_ref': session.name,
                'expires_at': fields.Datetime.to_string(session.expires_at) if session.expires_at else False,
                'refresh_expires_at': fields.Datetime.to_string(session.refresh_expires_at) if session.refresh_expires_at else False,
                'device_uid': session.device_uid or False,
            })
        return data

    def _session_payload(self, session, tokens=False):
        data = self._mobile_profile_payload(session.user_id, session=session)
        if tokens:
            data.update(tokens)
        return data

    def _session_device_values(self, params):
        return {
            'device_uid': self._get_clean_str(params, 'device_uid') or False,
            'device_name': self._get_clean_str(params, 'device_name') or False,
            'platform': self._get_clean_str(params, 'platform') or False,
            'app_version': self._get_clean_str(params, 'app_version') or False,
            'ip_address': request.httprequest.remote_addr or False,
            'user_agent': request.httprequest.headers.get('User-Agent') or False,
        }

    def _create_mobile_session_payload(self, user, params=None):
        params = params or {}
        token_data = request.env['acpec.mobile.session'].sudo().create_for_user(
            user.sudo(),
            self._session_device_values(params),
        )
        session = token_data.pop('session')
        return self._session_payload(session, tokens=token_data)

    def _require_fuel_group(self, user, expected):
        self._assert_mobile_only_user(user)
        if expected == 'client':
            if self._has_group_safe(user, 'acpec_fueltoken_base.group_fuel_user'):
                return True
        elif expected == 'station':
            if self._has_group_safe(user, 'acpec_fueltoken_base.group_fuel_station'):
                return True
        elif expected in ('manager', 'admin'):
            if self._has_group_safe(user, 'acpec_fueltoken_base.group_fuel_manager'):
                return True
        raise AccessError(_('Droits insuffisants pour cette opération.'))

    def _hash_public_value(self, value):
        return hashlib.sha256((value or '').encode('utf-8')).hexdigest()

