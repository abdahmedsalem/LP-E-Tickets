import hashlib
import logging
import traceback
import uuid
import time
from datetime import datetime
import re
from contextlib import contextmanager

from odoo import http, _, fields, api, SUPERUSER_ID
from odoo.exceptions import AccessError, ValidationError

from odoo.addons.acpec_mobile_auth.exceptions import MobileAuthRateLimitError
from odoo.http import request

_logger = logging.getLogger(__name__)


class MobileSensitiveActionError(AccessError):
    """Erreur sensible avec message public et raison technique auditée."""

    def __init__(self, code, public_message, debug_reason=False, reference=False):
        super().__init__(public_message)
        self.acpec_sensitive_code = code
        self.acpec_public_message = public_message
        self.acpec_debug_reason = debug_reason or public_message
        self.acpec_reference = reference or False


class MobileSignupNotAllowedError(ValidationError):
    """Refus signup/register non énumérant.

    Le message public reste générique. La raison technique est conservée
    pour l'audit interne et peut être exposée publiquement seulement via
    debug_reason lorsque le runtime public-auth debug l'autorise.
    """

    def __init__(self, debug_reason, company=False, public_debug_reason=False):
        super().__init__(debug_reason)
        self.acpec_debug_reason = debug_reason or 'mobile_signup_not_allowed'
        self.acpec_company = company
        self.acpec_public_debug_reason = public_debug_reason or False


class AcpecMobileAuthApiCommon(http.Controller):

    EMAIL_RE = re.compile(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')

    SENSITIVE_LOG_KEYS = frozenset({
        'access_token',
        'refresh_token',
        'authorization',
        'validation_key',
        'validation-token',
        'sms_validation_key',
        'sms_token',
        'token',
        'otp',
        'otp_code',
        'otp_dev_code',
        'dev_otp_code',
        'code',
        'secret_code',
        'action_code',
        'action_pin',
        'pin',
        'mobile_pin',
        'password',
        'qr_numeric_code',
        'qr_code',
        'public_code',
        'request_hash',
    })
    REDACTED_LOG_VALUE = '***REDACTED***'
    API_ERROR_REFERENCE_PREFIX = 'ERR'
    SECURITY_REFUSAL_REFERENCE_PREFIX = 'SEC'
    API_ERROR_SUMMARY_MAX_CHARS = 512
    API_ERROR_TRACEBACK_LOG_MAX_CHARS = 32768
    API_ERROR_PARAMS_LOG_MAX_CHARS = 4096

    SENSITIVE_PUBLIC_ERROR_FAMILIES = {
        'AUTH_REFUSED': 'Authentification impossible. Vérifiez les informations saisies.',
        'RATE_LIMITED': 'Trop de tentatives. Réessayez plus tard.',
        'DEVICE_NOT_ALLOWED': 'Cet appareil n’est pas autorisé pour cette opération.',
        'ACTION_REFUSED': 'Action impossible ou non autorisée.',
        'QR_NOT_USABLE': 'QR introuvable ou non utilisable.',
        'TRANSFER_REFUSED': 'Transfert impossible ou non autorisé.',
        'FORBIDDEN': 'Vous n’êtes pas autorisé à effectuer cette opération.',
        'REQUEST_REFUSED': 'Cette demande ne peut pas être traitée.',
        'SIGNUP_NOT_ALLOWED': 'Impossible de finaliser l’inscription avec ces informations.',
    }

    SENSITIVE_DEBUG_REASONS = frozenset({
        'auth_account_not_allowed',
        'auth_otp_not_found',
        'auth_otp_invalid',
        'auth_otp_expired',
        'auth_rate_limited',
        'signup_account_exists',
        'signup_not_allowed',
        'signup_pending_account_request',
        'register_otp_missing_or_unstable_device_uid_before_otp_consumption',
        'device_missing_uid',
        'device_pending_trust',
        'device_blocked',
        'device_not_trusted',
        'session_invalid',
        'action_code_missing',
        'action_code_invalid_key',
        'action_code_invalid',
        'action_code_locked',
        'pin_reset_required',
        'qr_not_found',
        'qr_wrong_company',
        'qr_not_active',
        'qr_expired',
        'qr_consumed',
        'recipient_not_found',
        'recipient_not_allowed',
        'recipient_self_transfer',
        'idempotency_payload_mismatch',
        'sensitive_action_denied',
    })

    SENSITIVE_PUBLIC_MESSAGES = {
        'purchase_create': "La demande d’achat a échoué. Réessayez ou contactez l’administrateur.",
        'qr_issue': "L’émission du QR a échoué. Réessayez ou contactez l’administrateur.",
        'qr_retirer': "Le retrait du QR a échoué. Réessayez ou contactez l’administrateur.",
        'qr_separer': "La séparation du QR a échoué. Réessayez ou contactez l’administrateur.",
        'carnet_transfer': "Le transfert a échoué. Réessayez ou contactez l’administrateur.",
        'station_qr_use': "La consommation du QR a échoué. Réessayez ou contactez l’administrateur.",
        'admin_sensitive_action': "L’action sensible a échoué. Réessayez ou contactez l’administrateur.",
        'carnet_type_create': "L’action sensible a échoué. Réessayez ou contactez l’administrateur.",
        'carnet_type_update': "L’action sensible a échoué. Réessayez ou contactez l’administrateur.",
        'carnet_type_delete': "L’action sensible a échoué. Réessayez ou contactez l’administrateur.",
        'purchase_approve': "L’action sensible a échoué. Réessayez ou contactez l’administrateur.",
        'purchase_reject': "L’action sensible a échoué. Réessayez ou contactez l’administrateur.",
        'station_create': "L’action sensible a échoué. Réessayez ou contactez l’administrateur.",
        'station_update': "L’action sensible a échoué. Réessayez ou contactez l’administrateur.",
        'station_disable': "L’action sensible a échoué. Réessayez ou contactez l’administrateur.",
    }

    def _redact_for_log(self, value):
        """Return a log-safe copy/string with secrets removed."""
        if isinstance(value, dict):
            safe = {}
            for key, item in value.items():
                key_text = str(key).strip().lower()
                if key_text in self.SENSITIVE_LOG_KEYS:
                    safe[key] = self.REDACTED_LOG_VALUE
                else:
                    safe[key] = self._redact_for_log(item)
            return safe

        if isinstance(value, (list, tuple)):
            return [self._redact_for_log(item) for item in value]

        if isinstance(value, set):
            return [self._redact_for_log(item) for item in sorted(value, key=lambda item: str(item))]

        return self._redact_text_for_log(value)

    def _redact_text_for_log(self, value):
        """Best-effort string scrubber for server logs.

        This is a safety net, not the primary protection.  Code must never
        intentionally interpolate OTP, PIN, action_code, tokens, raw QR codes
        or request hashes into exception messages.
        """
        text = '' if value in (None, False) else str(value)
        if not text:
            return text

        text = re.sub(
            r'(?i)(Authorization\s*:\s*Bearer\s+)[^\s,;]+',
            r'\1%s' % self.REDACTED_LOG_VALUE,
            text,
        )
        text = re.sub(
            r'(?i)(\bBearer\s+)[A-Za-z0-9._~+/=-]+',
            r'\1%s' % self.REDACTED_LOG_VALUE,
            text,
        )

        key_pattern = '|'.join(re.escape(key) for key in sorted(self.SENSITIVE_LOG_KEYS, key=len, reverse=True))
        quoted_pattern = r'(?i)([\"\']?(?:%s)[\"\']?\s*[:=]\s*)([\"\'])(.*?)(\2)' % key_pattern
        text = re.sub(
            quoted_pattern,
            lambda match: '%s%s%s%s' % (
                match.group(1),
                match.group(2),
                self.REDACTED_LOG_VALUE,
                match.group(2),
            ),
            text,
        )
        inline_pattern = r'(?i)((?<![\w-])(?:%s)(?![\w-])\s*[:=]\s*)[^\s,;\}\]\)]+' % key_pattern
        text = re.sub(
            inline_pattern,
            r'\1%s' % self.REDACTED_LOG_VALUE,
            text,
        )
        return text

    def _truncate_log_text(self, text, limit):
        text = '' if text in (None, False) else str(text)
        if not limit or len(text) <= limit:
            return text
        suffix = '... [tronqué]'
        return text[:max(limit - len(suffix), 0)] + suffix

    def _normalize_error_summary(self, text):
        text = self._redact_text_for_log(text)
        text = re.sub(r'\s+', ' ', text or '').strip()
        return self._truncate_log_text(text, self.API_ERROR_SUMMARY_MAX_CHARS)

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

    def _error_response(self, code, message, details=False, reference=False):
        payload = {
            'ok': False,
            'success': False,
            'error': {
                'code': code,
                'message': message,
            }
        }
        if reference:
            payload['error']['reference'] = reference
        if details:
            payload['error']['details'] = details
        return payload

    def _generate_mobile_api_error_reference(self):
        return '%s-%s-%s' % (
            self.API_ERROR_REFERENCE_PREFIX,
            datetime.utcnow().strftime('%Y%m%d-%H%M%S'),
            uuid.uuid4().hex[:6].upper(),
        )

    def _generate_mobile_security_reference(self):
        return '%s-%s-%s' % (
            self.SECURITY_REFUSAL_REFERENCE_PREFIX,
            datetime.utcnow().strftime('%Y%m%d-%H%M%S'),
            uuid.uuid4().hex[:6].upper(),
        )

    def _public_sensitive_message(self, public_code, purpose=False):
        return self.SENSITIVE_PUBLIC_ERROR_FAMILIES.get(
            public_code,
            self._sensitive_public_message(purpose),
        )

    def _normalize_sensitive_debug_reason(self, reason, fallback='sensitive_action_denied'):
        reason = (str(reason or '')).strip()
        if reason in self.SENSITIVE_DEBUG_REASONS:
            return reason
        lowered = reason.lower()
        if 'pending_account_request' in lowered or ('demande de compte' in lowered and 'attente' in lowered):
            return 'signup_pending_account_request'
        if 'already exists' in lowered or 'existe déjà' in lowered or 'déjà' in lowered:
            return 'signup_account_exists'
        if 'user_not_found' in lowered or 'not found' in lowered or 'introuvable' in lowered:
            return 'auth_account_not_allowed'
        if 'inactive' in lowered or 'inactif' in lowered:
            return 'auth_account_not_allowed'
        if 'not approved' in lowered or 'non approuvé' in lowered or 'rejeté' in lowered or 'rejected' in lowered:
            return 'auth_account_not_allowed'
        if 'expired' in lowered or 'expir' in lowered:
            return 'auth_otp_expired'
        if 'otp' in lowered and ('invalid' in lowered or 'invalide' in lowered):
            return 'auth_otp_invalid'
        if 'idempotency_conflict' in lowered or 'payload différent' in lowered:
            return 'idempotency_payload_mismatch'
        if 'action_code requis' in lowered or 'code d’action manquant' in lowered:
            return 'action_code_missing'
        if 'clé pin action invalide' in lowered or 'invalid_action_code_key' in lowered:
            return 'action_code_invalid_key'
        if 'pin mobile invalide' in lowered or 'invalid_action_code' in lowered:
            return 'action_code_invalid'
        if fallback in self.SENSITIVE_DEBUG_REASONS:
            return fallback
        return 'sensitive_action_denied'

    def _public_sensitive_code_for_refusal(self, code=False, purpose=False, event_type=False, public_code=False):
        if public_code:
            return public_code
        code = code or ''
        event_type = event_type or ''
        if code.startswith('DEVICE_') or event_type.startswith('device_'):
            return 'DEVICE_NOT_ALLOWED'
        if purpose == 'carnet_transfer' and code.startswith('RECIPIENT_'):
            return 'TRANSFER_REFUSED'
        if code.startswith('QR_') or purpose in ('station_qr_check', 'station_qr_use') and event_type.startswith('qr_'):
            return 'QR_NOT_USABLE'
        if code.startswith('IDEMPOTENCY_'):
            return 'REQUEST_REFUSED'
        if code in ('ACCESS_ERROR', 'FORBIDDEN'):
            return 'FORBIDDEN'
        return 'ACTION_REFUSED'

    def _public_auth_started_at(self):
        return time.monotonic()

    def _public_auth_min_latency_seconds(self):
        if hasattr(self, '_test_public_auth_min_latency_seconds'):
            return max(float(getattr(self, '_test_public_auth_min_latency_seconds') or 0.0), 0.0)
        try:
            policy = request.env['acpec.mobile.security.policy'].sudo()
            default_ms = 0 if policy.otp_dev_runtime_allowed() else 250
            value_ms = policy.get_int_param('acpec_mobile_auth.public_auth_min_latency_ms', default_ms)
            return max(float(value_ms or 0) / 1000.0, 0.0)
        except Exception:
            return 0.0

    def _apply_public_auth_min_latency(self, started_at=False):
        minimum = self._public_auth_min_latency_seconds()
        if not minimum or started_at is False:
            return
        elapsed = max(time.monotonic() - started_at, 0.0)
        remaining = minimum - elapsed
        if remaining > 0:
            time.sleep(remaining)

    def _request_params_for_error_log(self, params=False):
        if params is not False:
            return params or {}
        try:
            return getattr(request, 'params', {}) or {}
        except Exception:
            return {}

    def _mobile_api_error_marker_vals(self, exc, reference, params=False, operation=False):
        endpoint = self._request_path() or False
        exception_type = type(exc).__name__
        exception_summary = self._normalize_error_summary(str(exc) or exception_type)
        fingerprint_source = '%s|%s|%s' % (
            endpoint or '',
            exception_type or '',
            exception_summary or '',
        )
        fingerprint = hashlib.sha256(fingerprint_source.encode('utf-8')).hexdigest()[:32]

        user_id = False
        company_id = False
        try:
            env = self._api_env()
            user = env.user
            if user and user.exists():
                user_id = user.id
                company_id = user.company_id.id if user.company_id else False
        except Exception:
            user_id = False
            company_id = False

        return {
            'name': reference,
            'fingerprint': fingerprint,
            'code': 'SERVER_ERROR',
            'endpoint': endpoint,
            'operation': operation or False,
            'exception_type': exception_type,
            'exception_summary': exception_summary,
            'last_user_id': user_id,
            'last_company_id': company_id,
        }

    def _log_mobile_api_error_marker_committed(self, vals):
        vals = dict(vals or {})
        reference = vals.get('name') or vals.get('last_seen_reference') or False
        try:
            env = self._api_env()
            force_independent_cursor = getattr(self, '_force_independent_error_marker_cursor', False)
            if getattr(self, '_test_env', None) is not None and not force_independent_cursor:
                env['acpec.mobile.api.error.marker'].sudo().log_marker(**vals)
                return
            with env.registry.cursor() as cr:
                committed_env = api.Environment(cr, SUPERUSER_ID, dict(env.context))
                committed_env['acpec.mobile.api.error.marker'].sudo().log_marker(**vals)
        except Exception:
            _logger.exception('mobile_api_error_marker_create_failed reference=%s', reference)

    def _log_unhandled_mobile_api_exception(self, exc, params=False, operation=False):
        reference = self._generate_mobile_api_error_reference()
        params = self._request_params_for_error_log(params=params)
        marker_vals = self._mobile_api_error_marker_vals(
            exc,
            reference,
            params=params,
            operation=operation,
        )
        traceback_text = ''.join(traceback.format_exception(type(exc), exc, exc.__traceback__))
        traceback_text = self._redact_text_for_log(traceback_text)
        traceback_text = self._truncate_log_text(traceback_text, self.API_ERROR_TRACEBACK_LOG_MAX_CHARS)
        params_redacted = self._redact_for_log(params)
        params_redacted = self._truncate_log_text(params_redacted, self.API_ERROR_PARAMS_LOG_MAX_CHARS)

        _logger.error(
            'mobile_api_server_error reference=%s endpoint=%s operation=%s uid=%s company_id=%s exception_type=%s exception_summary=%s params_redacted=%s\n%s',
            reference,
            marker_vals.get('endpoint') or False,
            marker_vals.get('operation') or False,
            marker_vals.get('last_user_id') or False,
            marker_vals.get('last_company_id') or False,
            marker_vals.get('exception_type') or False,
            marker_vals.get('exception_summary') or False,
            params_redacted,
            traceback_text,
        )
        self._log_mobile_api_error_marker_committed(marker_vals)
        return reference

    def _handle_exception_response(self, exc, params=False, operation=False):
        if isinstance(exc, MobileSensitiveActionError):
            _logger.warning('%s', self._redact_for_log(exc.acpec_debug_reason))
            return self._error_response(
                exc.acpec_sensitive_code,
                exc.acpec_public_message,
                reference=getattr(exc, 'acpec_reference', False),
            )
        if isinstance(exc, MobileAuthRateLimitError):
            _logger.warning('%s', self._redact_for_log(str(exc)))
            return self._error_response('RATE_LIMITED', str(exc))
        if isinstance(exc, MobileSignupNotAllowedError):
            _logger.warning('%s', self._redact_for_log(exc.acpec_debug_reason))
            public_debug_reason = exc.acpec_public_debug_reason or self._public_auth_debug_reason(exc)
            return self._public_signup_not_allowed_response(debug_reason=public_debug_reason)
        if isinstance(exc, ValidationError):
            message = str(exc)
            lowered = message.lower()
            if 'idempotency_conflict' in lowered or 'payload différent' in lowered:
                return self._sensitive_refusal_response(
                    public_code='REQUEST_REFUSED',
                    debug_reason='idempotency_payload_mismatch',
                    purpose='idempotency_payload_mismatch',
                    params=params,
                    audit_code='IDEMPOTENCY_PAYLOAD_MISMATCH',
                )
            _logger.warning('%s', self._redact_for_log(str(exc)))
            return self._error_response('VALIDATION_ERROR', str(exc))
        if isinstance(exc, AccessError):
            _logger.warning('%s', self._redact_for_log(str(exc)))
            return self._error_response('ACCESS_ERROR', str(exc))
        reference = self._log_unhandled_mobile_api_exception(
            exc,
            params=params,
            operation=operation,
        )
        return self._error_response(
            'SERVER_ERROR',
            'Une erreur technique est survenue. Veuillez contacter le support.',
            reference=reference,
        )

    def _sensitive_public_message(self, purpose):
        # Ces messages sont déjà en français. Ne pas appeler _() ici :
        # ce helper est aussi utilisé depuis des contrôleurs/tests qui ne sont
        # pas des records Odoo et n'ont pas toujours env.uid disponible.
        return self.SENSITIVE_PUBLIC_MESSAGES.get(
            purpose or 'sensitive_action',
            "L’action sensible a échoué. Réessayez ou contactez l’administrateur.",
        )

    def _request_path(self):
        test_path = getattr(self, '_test_request_path', False)
        if test_path:
            return test_path
        try:
            return request.httprequest.path or False
        except Exception:
            return False

    def _request_ip(self):
        test_ip = getattr(self, '_test_request_ip', False)
        if test_ip:
            return test_ip
        try:
            return request.httprequest.remote_addr or False
        except Exception:
            return False

    def _request_user_agent(self):
        test_user_agent = getattr(self, '_test_user_agent', False)
        if test_user_agent:
            return test_user_agent
        try:
            return request.httprequest.headers.get('User-Agent') or False
        except Exception:
            return False

    def _action_code_present(self, params):
        value = (params or {}).get('action_code')
        return value not in (None, False, '')

    def _action_code_format_valid(self, params):
        value = (params or {}).get('action_code')
        value = str(value).strip() if value not in (None, False) else ''
        return bool(value.isdigit() and len(value) == 4)

    def _idempotency_key_for_audit(self, params):
        value = (params or {}).get('idempotency_key')
        value = str(value).strip() if value not in (None, False) else ''
        return value or False

    def _mobile_security_audit_vals(
        self, *,
        event_type,
        code,
        purpose=False,
        public_message=False,
        debug_reason=False,
        user=False,
        session=False,
        company=False,
        params=False,
        severity='warning',
        success=False,
        blocked=True,
        failed_count_before=False,
        failed_count_after=False,
        target_model=False,
        target_res_id=False,
        business_ref=False,
        reference=False,
    ):
        """Build plain audit values with no raw secret and no recordset.

        This helper deliberately returns only scalars so the committed-audit
        path can write from a separate cursor without carrying uncommitted
        recordsets across transactions.
        """
        user = user.sudo() if user and user.exists() else False
        session = session.sudo() if session and session.exists() else False
        company = company.sudo() if company and company.exists() else False

        audit_public_message = public_message
        if audit_public_message is False:
            audit_public_message = False if success else self._sensitive_public_message(purpose)

        return {
            'event_type': event_type,
            'severity': severity,
            'code': code,
            'reference': reference or False,
            'public_message': audit_public_message or False,
            'debug_reason': debug_reason or False,
            'user_id': user.id if user else False,
            'partner_id': user.partner_id.id if user and user.partner_id else False,
            'company_id': (user.company_id.id if user and user.company_id else (company.id if company else False)),
            'session_id': session.id if session else False,
            'device_uid': session.device_uid if session else False,
            'device_name': session.device_name if session else False,
            'device_trust_state': session.device_trust_state if session else False,
            'endpoint': self._request_path(),
            'operation': purpose or False,
            'idempotency_key': self._idempotency_key_for_audit(params),
            'ip_address': self._request_ip(),
            'user_agent': self._request_user_agent(),
            'success': bool(success),
            'blocked': bool(blocked),
            'action_code_present': self._action_code_present(params),
            'action_code_format_valid': self._action_code_format_valid(params),
            'failed_count_before': failed_count_before if failed_count_before is not False else False,
            'failed_count_after': failed_count_after if failed_count_after is not False else False,
            'target_model': target_model or False,
            'target_res_id': target_res_id or False,
            'business_ref': business_ref or False,
        }

    def _audit_in_transaction(self, vals):
        """Write audit in the current transaction, fail-closed.

        This is the only valid path for a sensitive action that has been
        authorized and whose business operation is about to be committed.
        There is intentionally no try/except here: if audit write fails, the
        caller's savepoint/transaction must rollback the business action too.
        """
        self._api_env()['acpec.mobile.security.audit.log'].sudo().log_event(**(vals or {}))

    def _audit_committed(self, vals):
        """Write a security-refusal audit in an independent committed cursor.

        Refusal evidence must survive the rollback/savepoint used by the denied
        business flow.  This helper receives only plain scalar values; never
        pass recordsets or data that depends on uncommitted rows.

        In Odoo 19, registry.cursor().__exit__ commits automatically when no
        exception is raised.  Do not add an explicit cr.commit() here.
        """
        vals = dict(vals or {})
        try:
            env = self._api_env()
            force_independent_cursor = getattr(self, '_force_independent_audit_cursor', False)
            if getattr(self, '_test_env', None) is not None and not force_independent_cursor:
                # Unit tests often use uncommitted fixture records that a second
                # cursor cannot see.  Production HTTP requests use the committed
                # cursor path below; tests can force that path with scalar-only
                # values through _force_independent_audit_cursor.
                env['acpec.mobile.security.audit.log'].sudo().log_event(**vals)
                return
            with env.registry.cursor() as cr:
                committed_env = api.Environment(cr, SUPERUSER_ID, dict(env.context))
                committed_env['acpec.mobile.security.audit.log'].sudo().log_event(**vals)
        except Exception:
            _logger.exception('Impossible d’écrire le journal d’audit sécurité mobile refusé')

    def _log_mobile_security_audit_event(
        self, *,
        event_type,
        code,
        purpose=False,
        public_message=False,
        debug_reason=False,
        user=False,
        session=False,
        company=False,
        params=False,
        severity='warning',
        success=False,
        blocked=True,
        failed_count_before=False,
        failed_count_after=False,
        target_model=False,
        target_res_id=False,
        business_ref=False,
        reference=False,
    ):
        try:
            vals = self._mobile_security_audit_vals(
                event_type=event_type,
                severity=severity,
                code=code,
                purpose=purpose,
                public_message=public_message,
                debug_reason=debug_reason,
                user=user,
                session=session,
                company=company,
                params=params,
                success=success,
                blocked=blocked,
                failed_count_before=failed_count_before,
                failed_count_after=failed_count_after,
                target_model=target_model,
                target_res_id=target_res_id,
                business_ref=business_ref,
                reference=reference,
            )
            self._audit_in_transaction(vals)
        except Exception:
            _logger.exception('Impossible d’écrire le journal d’audit sécurité mobile')
            if getattr(self, '_test_env', None) is not None:
                raise

    def _raise_sensitive_action_error(
        self, *,
        code,
        debug_reason,
        purpose=False,
        event_type='sensitive_action_denied',
        user=False,
        session=False,
        params=False,
        severity='warning',
        failed_count_before=False,
        failed_count_after=False,
        public_code=False,
    ):
        public_code = self._public_sensitive_code_for_refusal(
            code=code,
            purpose=purpose,
            event_type=event_type,
            public_code=public_code,
        )
        public_message = self._public_sensitive_message(public_code, purpose=purpose)
        reference = self._generate_mobile_security_reference()
        audit_debug_reason = self._normalize_sensitive_debug_reason(
            debug_reason,
            fallback=event_type or 'sensitive_action_denied',
        )
        vals = self._mobile_security_audit_vals(
            event_type=event_type,
            severity=severity,
            code=code,
            purpose=purpose,
            public_message=public_message,
            debug_reason=audit_debug_reason,
            user=user,
            session=session,
            params=params,
            success=False,
            blocked=True,
            failed_count_before=failed_count_before,
            failed_count_after=failed_count_after,
            reference=reference,
        )
        self._audit_committed(vals)
        raise MobileSensitiveActionError(public_code, public_message, audit_debug_reason, reference=reference)

    def _sensitive_refusal_response(
        self, *,
        public_code,
        debug_reason,
        purpose=False,
        params=False,
        user=False,
        session=False,
        company=False,
        event_type='sensitive_action_denied',
        severity='warning',
        audit_code=False,
        target_model=False,
        target_res_id=False,
        business_ref=False,
    ):
        reference = self._generate_mobile_security_reference()
        public_message = self._public_sensitive_message(public_code, purpose=purpose)
        audit_debug_reason = self._normalize_sensitive_debug_reason(
            debug_reason,
            fallback=event_type or 'sensitive_action_denied',
        )
        vals = self._mobile_security_audit_vals(
            event_type=event_type,
            severity=severity,
            code=audit_code or public_code,
            purpose=purpose,
            public_message=public_message,
            debug_reason=audit_debug_reason,
            user=user,
            session=session,
            company=company,
            params=params,
            success=False,
            blocked=True,
            target_model=target_model,
            target_res_id=target_res_id,
            business_ref=business_ref,
            reference=reference,
        )
        self._audit_committed(vals)
        return self._error_response(public_code, public_message, reference=reference)


    def _classify_pin_failure(self, exc, user, failed_count_before=False):
        debug_reason = str(exc)
        failed_count_after = user.mobile_pin_failed_count or 0

        if user.mobile_pin_required or not user.mobile_pin_set:
            return 'pin_hard_blocked', 'PIN_RESET_REQUIRED', 'critical', failed_count_after

        if user.mobile_pin_locked_until:
            return 'pin_locked', 'ACTION_CODE_LOCKED', 'warning', failed_count_after

        if failed_count_after and failed_count_after > (failed_count_before or 0):
            return 'invalid_action_code', 'INVALID_ACTION_CODE', 'warning', failed_count_after

        if 'défini' in debug_reason or 'defini' in debug_reason:
            return 'pin_reset_required', 'PIN_RESET_REQUIRED', 'warning', failed_count_after

        return 'sensitive_action_denied', 'ACTION_CODE_DENIED', 'warning', failed_count_after

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
        return request.env["acpec.mobile.security.policy"].sudo().get_bool(key, default=default)
    def _get_config_int(self, key, default=0):
        return request.env["acpec.mobile.security.policy"].sudo().get_int_param(key, default)
    def _validate_selection(self, value, key, allowed_values):
        if value and value not in allowed_values:
            raise ValidationError(
                _("Invalid value for '%s'. Allowed values: %s") % (
                    key, ", ".join(allowed_values)
                )
            )

    def _public_auth_debug_allowed(self):
        return request.env['acpec.mobile.security.policy'].sudo().otp_dev_runtime_allowed()

    def _with_public_auth_debug(self, payload, debug_reason=False):
        if debug_reason and self._public_auth_debug_allowed():
            if isinstance(payload, dict) and isinstance(payload.get('error'), dict):
                payload['error']['debug_reason'] = debug_reason
            elif isinstance(payload, dict):
                payload['debug_reason'] = debug_reason
        return payload

    def _public_auth_debug_reason(self, exc):
        message = (str(exc) or '').lower()
        if 'demande de compte' in message and 'attente' in message:
            return 'signup_pending_account_request'
        if 'déjà' in message or 'already exists' in message:
            return 'signup_account_exists'
        if 'introuvable' in message or 'not found' in message:
            return 'auth_account_not_allowed'
        if 'inactif' in message or 'inactive' in message:
            return 'auth_account_not_allowed'
        if 'non approuvé' in message or 'not approved' in message:
            return 'auth_account_not_allowed'
        if 'rejeté' in message or 'rejected' in message:
            return 'auth_account_not_allowed'
        if 'expir' in message or 'expired' in message:
            return 'auth_otp_expired'
        if 'otp' in message and ('invalide' in message or 'invalid' in message):
            return 'auth_otp_invalid'
        return 'auth_account_not_allowed'

    def _public_otp_request_accepted_response(self, debug_reason=False, started_at=False):
        self._apply_public_auth_min_latency(started_at)
        return self._with_public_auth_debug(self._json_response({
            'message': _('Si les informations sont valides, un code de vérification sera envoyé.'),
        }), debug_reason=debug_reason)

    def _public_otp_invalid_response(self, debug_reason=False, params=False, purpose='otp_verify', started_at=False):
        reference = self._generate_mobile_security_reference()
        public_code = 'AUTH_REFUSED'
        public_message = self._public_sensitive_message(public_code, purpose=purpose)
        audit_debug_reason = self._normalize_sensitive_debug_reason(
            debug_reason,
            fallback='auth_otp_invalid',
        )
        self._log_mobile_security_audit_event(
            event_type='sensitive_action_denied',
            severity='warning',
            code=public_code,
            purpose=purpose,
            public_message=public_message,
            debug_reason=audit_debug_reason,
            params=params,
            success=False,
            blocked=True,
            reference=reference,
        )
        self._apply_public_auth_min_latency(started_at)
        return self._with_public_auth_debug(self._error_response(
            public_code,
            public_message,
            reference=reference,
        ), debug_reason=audit_debug_reason)

    def _public_account_not_found_response(self, debug_reason=False, started_at=False):
        # Do not publicly refuse request-otp login/reset for an unknown account:
        # a public error would still be an account-existence oracle.  Keep the
        # same accepted shape as a valid OTP request; the SMS side effect remains
        # naturally absent because no challenge is created.
        return self._public_otp_request_accepted_response(
            debug_reason=debug_reason,
            started_at=started_at,
        )

    def _public_signup_not_allowed_response(self, debug_reason=False, reference=False):
        return self._with_public_auth_debug(self._error_response(
            'SIGNUP_NOT_ALLOWED',
            'Impossible de finaliser l’inscription avec ces informations.',
            reference=reference,
        ), debug_reason=debug_reason)

    def _audit_mobile_signup_denial(
        self, *,
        debug_reason,
        params=False,
        company=False,
        public_debug_reason=False,
        reference=False,
    ):
        """Audit internal signup/register denial without raising afterward.

        Important: callers must use this from controller except/return paths,
        not from inside savepoints followed by raise, otherwise the audit row
        can be lost by rollback.
        """
        public_message = 'Impossible de finaliser l’inscription avec ces informations.'
        company = company.sudo() if company and company.exists() else False
        self._log_mobile_security_audit_event(
            event_type='mobile_signup_not_allowed',
            severity='warning',
            code='SIGNUP_NOT_ALLOWED',
            purpose='register',
            public_message=public_message,
            debug_reason=debug_reason or public_debug_reason or 'mobile_signup_not_allowed',
            company=company,
            params=params,
            success=False,
            blocked=True,
            target_model='res.company' if company else False,
            target_res_id=company.id if company else False,
            business_ref=company.display_name if company else False,
            reference=reference,
        )

    def _mobile_signup_not_allowed_response(
        self,
        exc=False,
        *,
        params=False,
        company=False,
        debug_reason=False,
        public_debug_reason=False,
    ):
        """Log internal technical denial then return generic public payload."""
        if exc:
            debug_reason = getattr(exc, 'acpec_debug_reason', False) or str(exc)
            company = company or getattr(exc, 'acpec_company', False)
            public_debug_reason = (
                getattr(exc, 'acpec_public_debug_reason', False)
                or public_debug_reason
                or self._public_auth_debug_reason(exc)
            )

        reference = self._generate_mobile_security_reference()
        self._audit_mobile_signup_denial(
            debug_reason=self._normalize_sensitive_debug_reason(debug_reason, fallback='signup_not_allowed'),
            params=params,
            company=company,
            public_debug_reason=public_debug_reason,
            reference=reference,
        )
        return self._public_signup_not_allowed_response(
            debug_reason=public_debug_reason or self._public_auth_debug_reason(Exception(debug_reason or '')),
            reference=reference,
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
            raise MobileSignupNotAllowedError(
                _('This company does not accept mobile application registration.'),
                company=company,
                public_debug_reason='signup_not_allowed',
            )
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

    def _parse_signup_identifier(self, signup_identifier, signup_identifier_type=False):
        """Parse the public signup identity with a strict optional type contract.

        If signup_identifier_type is omitted, legacy auto-detection is kept:
        values containing '@' are treated as email, everything else as phone.

        Phone identity is strict at input: exactly 8 digits and first digit 2,
        3 or 4. No +222/222 prefix, spaces, dashes or other normalization is
        accepted. The UI may assist entry, but the backend does not repair an
        identity value.
        """
        identifier = (signup_identifier or '').strip()
        requested_type = (signup_identifier_type or '').strip().lower()
        if not identifier:
            raise ValidationError(_('Signup identifier is required.'))
        if requested_type and requested_type not in ('phone', 'email'):
            raise ValidationError(_('signup_identifier_type must be phone or email.'))

        if requested_type == 'email' or (not requested_type and '@' in identifier):
            email = identifier.lower()
            self._validate_email(email)
            return {
                'signup_identifier': email,
                'signup_identifier_type': 'email',
                'login': email,
                'phone': False,
                'email': email,
            }

        self._validate_phone_number(identifier)
        return {
            'signup_identifier': identifier,
            'signup_identifier_type': 'phone',
            'login': identifier,
            'phone': identifier,
            'email': False,
        }

    def _mobile_signup_group_ids(self):
        """Return the technical baseline groups for mobile OTP-created users.

        A FuelToken mobile user is technically an Odoo portal user, but is
        functionally mobile-only. Application roles are assigned separately by
        controlled back-office flows.
        """
        group_ids = []
        for xmlid in (
            'base.group_portal',
            'acpec_mobile_auth.group_mobile_auth_user',
        ):
            group = request.env.ref(xmlid, raise_if_not_found=False)
            if group:
                group_ids.append(group.id)
        return group_ids

    def _create_mobile_signup_account(self, *, name, signup_identifier, secret_code, company, email=False, note=False, signup_identifier_type=False):
        identifier_vals = self._parse_signup_identifier(
            signup_identifier,
            signup_identifier_type=signup_identifier_type,
        )
        self._validate_secret_code(secret_code)

        user_model = request.env['res.users'].sudo().with_context(active_test=False)

        user_domain = [('login', '=', identifier_vals['login'])]
        if identifier_vals['signup_identifier_type'] == 'phone':
            user_domain = ['|', ('login', '=', identifier_vals['login']), ('mobile_phone', '=', identifier_vals['phone'])]
        else:
            user_domain = ['|', ('login', '=', identifier_vals['login']), ('email', '=', identifier_vals['email'])]

        existing_user = user_model.search(user_domain, limit=1)
        if existing_user:
            raise MobileSignupNotAllowedError(
                _('A mobile account already exists for this identifier.'),
                company=company,
                public_debug_reason='account_exists',
            )

        email_value = (email or identifier_vals['email'] or '').strip()

        mobile_group_ids = self._mobile_signup_group_ids()

        user_vals = {
            'name': name,
            'login': identifier_vals['login'],
            'company_id': company.id,
            'company_ids': [(6, 0, [company.id])],
            'active': True,
            'mobile_only': True,
            'mobile_state': 'pending',
            'password': user_model._acpec_mobile_unusable_password(),
        }
        if mobile_group_ids:
            user_vals['group_ids'] = [(6, 0, mobile_group_ids)]
        if identifier_vals['phone']:
            user_vals['mobile_phone'] = identifier_vals['phone']

        user = request.env['res.users'].sudo().with_context(no_reset_password=True).create(user_vals)
        partner = user.partner_id.sudo()
        partner_vals = {
            'acpec_is_mobile_partner': True,
        }
        if identifier_vals['phone'] and not partner.ref:
            partner_vals['ref'] = 'MOB:%s' % identifier_vals['phone']
        partner.write(partner_vals)
        user.set_mobile_pin(secret_code)

        request_model = request.env['acpec.mobile.auth.account.request'].sudo()
        request_vals = {
            'name_display': name,
            'signup_identifier': identifier_vals['signup_identifier'],
            'signup_identifier_type': identifier_vals['signup_identifier_type'],
            'company_id': company.id,
            'state': 'pending',
            'user_id': user.id,
        }

        # Keep this creation resilient across small model evolutions.
        if 'partner_id' in request_model._fields:
            request_vals['partner_id'] = partner.id
        if 'phone' in request_model._fields and identifier_vals['phone']:
            request_vals['phone'] = identifier_vals['phone']
        if 'email' in request_model._fields and email_value:
            request_vals['email'] = email_value
        if 'login' in request_model._fields:
            request_vals['login'] = identifier_vals['login']
        if 'note' in request_model._fields and note:
            request_vals['note'] = note

        account_request = request_model.create(request_vals)
        return partner, user, account_request

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
        if not getattr(user, 'mobile_only', False):
            raise AccessError(_('Ce compte n’est pas un compte mobile-only FuelToken.'))

        required_xmlids = (
            'base.group_portal',
            'acpec_mobile_auth.group_mobile_auth_user',
        )
        forbidden_xmlids = (
            'base.group_user',
            'base.group_public',
            'acpec_mobile_auth.group_mobile_auth_admin',
            'acpec_fueltoken_base.group_fuel_admin',
        )

        for xmlid in required_xmlids:
            if not self._has_group_safe(user, xmlid):
                raise AccessError(_('Compte mobile FuelToken incomplet ou mal configuré.'))

        for xmlid in forbidden_xmlids:
            if self._has_group_safe(user, xmlid):
                raise AccessError(_('Ce compte n’est pas autorisé à utiliser l’application mobile FuelToken.'))

    def _require_mobile_auth(self):
        session = self._get_mobile_session(required=True)
        user = session.user_id.sudo()
        self._assert_mobile_only_user(user)
        return user

    def _require_trusted_mobile_auth(self):
        """Guard for business mobile reads and actions requiring a trusted device.

        Login, signup, OTP, refresh and minimal profile/enrollment endpoints must
        keep using _require_mobile_auth() so a pending device can still learn its
        approval state. Business reads/actions must use this helper to avoid
        exposing wallet, QR, purchase, station or admin data to pending devices.
        """
        session = self._get_mobile_session(required=True)
        user = session.user_id.sudo()
        self._assert_mobile_only_user(user)

        if not session.device_uid:
            raise AccessError('Device mobile non identifié.')

        if session.device_trust_state != 'trusted':
            if session.device_trust_state == 'pending_trust':
                raise AccessError('Device mobile en attente de validation.')
            if session.device_trust_state == 'blocked':
                raise AccessError('Device mobile bloqué.')
            raise AccessError('Device mobile non approuvé.')

        return user

    def _require_trusted_sensitive(self):
        """Guard for sensitive mobile operations before action-code validation."""
        return self._require_trusted_mobile_auth()

    def _get_sensitive_action_pin(self, params):
        """Return the canonical server-side PIN for a sensitive action.

        V1 accepts exactly one request key: ``action_code``.
        Historical aliases (``action_pin``, ``pin``, ``secret_code``) are
        deliberately rejected.  In particular, ``secret_code`` is reserved for
        signup / initial mobile PIN setup and must not be reused as an action
        confirmation field.
        """
        params = params or {}
        forbidden_aliases = ('action_pin', 'pin', 'secret_code')
        used_aliases = [
            key for key in forbidden_aliases
            if params.get(key) not in (None, False, '')
        ]
        if used_aliases:
            raise ValidationError(
                "Clé PIN action invalide: utilisez uniquement action_code."
            )
        pin = params.get('action_code')
        if pin in (None, False, ''):
            raise ValidationError('action_code requis pour confirmer cette action sensible.')
        return str(pin)

    def _require_sensitive_action_pin(self, params=None, purpose='sensitive_action', log_allowed=True, return_audit_vals=False):
        """Require trusted device + server-side mobile PIN for a concrete sensitive action.

        Le PIN/action_code brut n’est jamais stocké dans l’audit. Le mobile
        reçoit uniquement un message public générique, tandis que la raison
        technique est conservée dans acpec.mobile.security.audit.log.
        """
        params = params or {}

        session = self._get_mobile_session(required=True)
        user = session.user_id.sudo()
        self._assert_mobile_only_user(user)

        if not session.device_uid:
            self._raise_sensitive_action_error(
                code='DEVICE_MISSING_UID',
                event_type='device_missing_uid',
                purpose=purpose,
                debug_reason='Device mobile non identifié.',
                user=user,
                session=session,
                params=params,
            )

        if session.device_trust_state != 'trusted':
            if session.device_trust_state == 'pending_trust':
                self._raise_sensitive_action_error(
                    code='DEVICE_PENDING_TRUST',
                    event_type='device_pending_trust',
                    purpose=purpose,
                    debug_reason='Device mobile en attente de validation.',
                    user=user,
                    session=session,
                    params=params,
                )

            if session.device_trust_state == 'blocked':
                self._raise_sensitive_action_error(
                    code='DEVICE_BLOCKED',
                    event_type='device_blocked',
                    purpose=purpose,
                    debug_reason='Device mobile bloqué.',
                    user=user,
                    session=session,
                    params=params,
                    severity='error',
                )

            self._raise_sensitive_action_error(
                code='DEVICE_NOT_TRUSTED',
                event_type='device_not_trusted',
                purpose=purpose,
                debug_reason='Device mobile non approuvé.',
                user=user,
                session=session,
                params=params,
            )

        try:
            pin = self._get_sensitive_action_pin(params)
        except ValidationError as exc:
            reason = str(exc)
            code = 'MISSING_ACTION_CODE'
            event_type = 'missing_action_code'

            forbidden_alias_used = any(
                params.get(key) not in (None, False, '')
                for key in ('action_pin', 'pin', 'secret_code')
            )
            if forbidden_alias_used:
                code = 'INVALID_ACTION_CODE_KEY'
                event_type = 'invalid_action_code_key'

            self._raise_sensitive_action_error(
                code=code,
                event_type=event_type,
                purpose=purpose,
                debug_reason=reason,
                user=user,
                session=session,
                params=params,
            )

        user.invalidate_recordset([
            'mobile_pin_failed_count',
            'mobile_pin_locked_until',
            'mobile_pin_set',
            'mobile_pin_required',
        ])
        failed_count_before = user.mobile_pin_failed_count or 0

        try:
            user.check_mobile_pin(pin, purpose=purpose)
        except AccessError as exc:
            user.invalidate_recordset([
                'mobile_pin_failed_count',
                'mobile_pin_locked_until',
                'mobile_pin_set',
                'mobile_pin_required',
            ])

            event_type, code, severity, failed_count_after = self._classify_pin_failure(
                exc,
                user,
                failed_count_before=failed_count_before,
            )

            self._raise_sensitive_action_error(
                code=code,
                event_type=event_type,
                severity=severity,
                purpose=purpose,
                debug_reason=str(exc),
                user=user,
                session=session,
                params=params,
                failed_count_before=failed_count_before,
                failed_count_after=failed_count_after,
            )

        user.invalidate_recordset([
            'mobile_pin_failed_count',
            'mobile_pin_locked_until',
        ])
        failed_count_after = user.mobile_pin_failed_count or 0

        allowed_audit_vals = self._mobile_security_audit_vals(
            event_type='sensitive_action_allowed',
            severity='info',
            code='ACTION_CODE_VALID',
            purpose=purpose,
            public_message=False,
            debug_reason='Action code validé par le backend.',
            user=user,
            session=session,
            params=params,
            success=True,
            blocked=False,
            failed_count_before=failed_count_before,
            failed_count_after=failed_count_after,
        )

        if log_allowed:
            self._audit_in_transaction(allowed_audit_vals)

        if return_audit_vals:
            return user, allowed_audit_vals
        return user

    @contextmanager
    def _sensitive_action_transaction(self, params=None, purpose='sensitive_action'):
        """Run an authorized sensitive action and its success audit atomically.

        Security refusals are audited by _require_sensitive_action_pin() before
        this savepoint is opened.  Once the action_code is valid, the allowed
        audit is written only after the business action succeeds and in the
        same savepoint.  If the allowed-audit write fails, the savepoint rolls
        back the business action and re-raises the audit exception.  Do not
        replace this with a try/except that swallows audit errors.
        """
        user, allowed_audit_vals = self._require_sensitive_action_pin(
            params or {},
            purpose=purpose,
            log_allowed=False,
            return_audit_vals=True,
        )
        with self._api_env().cr.savepoint():
            yield user
            self._audit_in_transaction(allowed_audit_vals)

    def _mobile_profile_payload(self, user, session=False):
        data = {
            'uid': user.id,
            'name': user.name,
            'login': user.login,
            'partner_id': user.partner_id.id,
            'mobile_phone': user.mobile_phone,
            'email': user.email,
            'mobile_state': user.mobile_state,
            'mobile_only': bool(user.mobile_only),
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
                'device_trust_state': session.device_trust_state or False,
                'device_trusted_at': fields.Datetime.to_string(session.device_trusted_at) if session.device_trusted_at else False,
                'device_trust_required_for_sensitive': True,
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
        raise AccessError('Droits insuffisants pour cette opération.')

    def _hash_public_value(self, value):
        return hashlib.sha256((value or '').encode('utf-8')).hexdigest()
