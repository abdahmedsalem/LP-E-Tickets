from odoo import http, _, fields
from odoo.http import request
from odoo.exceptions import AccessError, ValidationError

from odoo.addons.acpec_mobile_auth.controllers.api_common import AcpecMobileAuthApiCommon, MobileSignupNotAllowedError


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
                    return self._mobile_signup_not_allowed_response(
                        params=kwargs,
                        debug_reason='A mobile account already exists for this identifier.',
                        public_debug_reason='account_exists',
                    )

            try:
                challenge, code = request.env['acpec.mobile.auth.otp'].sudo().request_otp(
                    identifier,
                    purpose=purpose,
                    request_ip=self._request_ip(),
                )
            except AccessError as exc:
                debug_reason = self._public_auth_debug_reason(exc)
                if purpose == 'register':
                    return self._mobile_signup_not_allowed_response(
                        params=kwargs,
                        debug_reason=str(exc),
                        public_debug_reason=debug_reason,
                    )
                if purpose in ('login', 'reset') and debug_reason == 'user_not_found':
                    return self._public_account_not_found_response(debug_reason=debug_reason)
                return self._public_otp_request_accepted_response(debug_reason=debug_reason)
            data = {
                'challenge_id': challenge.id,
                'challenge_ref': challenge.name,
                'identifier': challenge.identifier,
                'purpose': challenge.purpose,
                'expires_at': fields.Datetime.to_string(challenge.expires_at) if challenge.expires_at else False,
                'delivery': 'configured_provider',
            }
            if request.env['acpec.mobile.security.policy'].sudo().otp_dev_mode_enabled():
                data['delivery'] = 'dev_fixed_otp'
            data['otp_challenge_id'] = data['challenge_id']
            data['otp_challenge_ref'] = data['challenge_ref']
            data['otp_expires_at'] = data['expires_at']
            data['otp_delivery'] = data['delivery']
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
                return self._public_otp_invalid_response(debug_reason='otp_not_found')
            reset_secret_code = False
            reset_user = False
            if challenge.purpose == 'reset':
                invalid_reset_aliases = ('action_code', 'action_pin', 'pin', 'new_pin')
                used_aliases = [
                    key for key in invalid_reset_aliases
                    if kwargs.get(key) not in (None, False, '')
                ]
                if used_aliases:
                    return self._error_response(
                        'VALIDATION_ERROR',
                        'Cle PIN reset invalide: utilisez uniquement secret_code.',
                    )

                reset_secret_code = self._get_clean_str(kwargs, 'secret_code')
                if not reset_secret_code:
                    return self._error_response('SECRET_CODE_REQUIRED', _('Secret code is required.'))

                reset_user = challenge.user_id.sudo()
                if not reset_user:
                    return self._public_otp_invalid_response(debug_reason='reset_user_not_found')

                # Validate the new PIN before consuming the OTP.
                reset_user._validate_mobile_pin(reset_secret_code)

            register_name = False
            register_secret_code = False
            register_email = False
            register_note = False
            register_company_id = False
            register_company = False

            if challenge.purpose == 'register':
                register_name = self._get_clean_str(kwargs, 'name')
                register_secret_code = self._get_clean_str(kwargs, 'secret_code')
                register_email = self._get_clean_str(kwargs, 'email')
                register_note = self._get_clean_str(kwargs, 'note')
                audit_company = request.env.company

                try:
                    register_company_id = self._get_optional_int(kwargs, 'company_id', False)
                except (TypeError, ValueError, ValidationError):
                    return self._mobile_signup_not_allowed_response(
                        params=kwargs,
                        company=audit_company,
                        debug_reason='register_otp_invalid_company_id_before_otp_consumption',
                        public_debug_reason='signup_not_allowed',
                    )

                if register_company_id:
                    candidate_company = request.env['res.company'].sudo().browse(register_company_id)
                    if candidate_company.exists():
                        audit_company = candidate_company

                device_uid = self._get_clean_str(kwargs, 'device_uid')
                session_model = request.env['acpec.mobile.session'].sudo()
                if not session_model._is_stable_device_uid(device_uid):
                    return self._mobile_signup_not_allowed_response(
                        params=kwargs,
                        company=audit_company,
                        debug_reason='register_otp_missing_or_unstable_device_uid_before_otp_consumption',
                        public_debug_reason='signup_not_allowed',
                    )

                if not register_name:
                    return self._error_response('NAME_REQUIRED', 'Name is required.')
                if not register_secret_code:
                    return self._error_response('SECRET_CODE_REQUIRED', 'Secret code is required.')

                try:
                    request.env['res.users'].sudo()._validate_mobile_pin(register_secret_code)
                except ValidationError:
                    return self._error_response(
                        'SECRET_CODE_INVALID',
                        'Le PIN mobile doit contenir exactement 4 chiffres.',
                    )

                try:
                    register_company = self._get_company(register_company_id)
                except MobileSignupNotAllowedError as exc:
                    return self._mobile_signup_not_allowed_response(
                        exc,
                        params=kwargs,
                        company=audit_company,
                    )

            try:
                user = challenge.verify(code)
            except (AccessError, ValidationError) as exc:
                return self._public_otp_invalid_response(
                    debug_reason=self._public_auth_debug_reason(exc)
                )
            if challenge.purpose == 'reset':
                if not user or user.id != reset_user.id:
                    return self._public_otp_invalid_response(debug_reason='reset_user_mismatch')

                user.sudo().set_mobile_pin(reset_secret_code)
                payload = self._create_mobile_session_payload(user, kwargs)
                payload.update({
                    'auth_method': 'otp',
                    'pin_reset': True,
                    'message': 'PIN mobile reinitialise.',
                })
                return self._json_response(payload)

            if challenge.purpose == 'register':
                name = register_name
                secret_code = register_secret_code
                email = register_email
                note = register_note
                company = register_company
                identifier_vals = self._parse_signup_identifier(challenge.identifier or identifier)

                account_request = False
                if not user:
                    try:
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
                    except MobileSignupNotAllowedError as exc:
                        return self._mobile_signup_not_allowed_response(
                            exc,
                            params=kwargs,
                            company=company,
                        )
                    except (AccessError, ValidationError) as exc:
                        return self._mobile_signup_not_allowed_response(
                            params=kwargs,
                            company=company,
                            debug_reason=str(exc),
                            public_debug_reason=self._public_auth_debug_reason(exc),
                        )
                else:
                    account_request = request.env['acpec.mobile.auth.account.request'].sudo().search([
                        ('user_id', '=', user.id),
                        ('state', '=', 'pending'),
                    ], order='id desc', limit=1)

                # L’OTP d’inscription prouve le contrôle du numéro et crée
                # un compte mobile connectable pour enrôler l’appareil.
                # Il n’accorde aucun accès métier Tickets Carburant.
                user.sudo().write({
                    'active': True,
                    'mobile_state': 'self_registered',
                })

                if account_request and account_request.state == 'pending':
                    # Patch42C closes the account request because OTP registration
                    # finalized the account creation. Do not call action_approve():
                    # device trust and business access remain pending separately.
                    account_request.write({
                        'state': 'approved',
                        'reviewed_at': fields.Datetime.now(),
                    })

                payload = self._create_mobile_session_payload(user, kwargs)
                payload.update({
                    'auth_method': 'otp',
                    'pending_approval': True,
                    'account_request_id': account_request.id if account_request else False,
                    'message': 'Compte mobile créé. Appareil en attente de validation.',
                })
                return self._json_response(payload)
            payload = self._create_mobile_session_payload(user, kwargs)
            payload['auth_method'] = 'otp'
            return self._json_response(payload)
        except Exception as exc:
            return self._handle_exception_response(exc)
