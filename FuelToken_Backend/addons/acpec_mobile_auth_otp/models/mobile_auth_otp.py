import hmac
import hashlib
import logging
import os
import secrets

from dateutil.relativedelta import relativedelta

from odoo import _, api, fields, models
from odoo.exceptions import AccessError, ValidationError

from odoo.addons.acpec_mobile_auth.exceptions import MobileAuthRateLimitError

_logger = logging.getLogger(__name__)

OTP_SMS_CODE_LENGTH_DEFAULT = 6
OTP_SMS_CODE_LENGTH_MIN = 6
OTP_SMS_CODE_LENGTH_MAX = 6


class AcpecMobileAuthOtp(models.Model):
    _name = 'acpec.mobile.auth.otp'
    _description = 'ACPEC Mobile OTP Challenge'
    _inherit = ['mail.thread', 'mail.activity.mixin']
    _order = 'create_date desc, id desc'

    name = fields.Char(default='New', readonly=True, copy=False, index=True)
    identifier = fields.Char(required=True, index=True)
    mobile = fields.Char(index=True)
    email = fields.Char(index=True)
    request_ip = fields.Char(index=True, copy=False)
    otp_hash = fields.Char(required=True, copy=False)
    salt = fields.Char(required=True, copy=False)
    purpose = fields.Selection([
        ('login', 'Login'),
        ('register', 'Register'),
        ('reset', 'Reset'),
    ], default='login', required=True, index=True)
    user_id = fields.Many2one('res.users', index=True, ondelete='cascade')
    partner_id = fields.Many2one('res.partner', related='user_id.partner_id', store=True, readonly=True, index=True)
    company_id = fields.Many2one('res.company', related='user_id.company_id', store=True, readonly=True, index=True)
    expires_at = fields.Datetime(required=True, index=True)
    attempt_count = fields.Integer(default=0, readonly=True)
    max_attempts = fields.Integer(default=5, required=True)
    verified_at = fields.Datetime(readonly=True, copy=False)
    blocked_until = fields.Datetime(readonly=True, copy=False)
    state = fields.Selection([
        ('pending', 'Pending'),
        ('verified', 'Verified'),
        ('expired', 'Expired'),
        ('blocked', 'Blocked'),
        ('cancelled', 'Cancelled'),
    ], default='pending', required=True, tracking=True, index=True)

    @api.model_create_multi
    def create(self, vals_list):
        sequence = self.env['ir.sequence']
        for vals in vals_list:
            if vals.get('name', 'New') == 'New':
                vals['name'] = sequence.next_by_code('acpec.mobile.auth.otp') or 'New'
        return super().create(vals_list)

    @api.model
    def _hash_otp(self, code, salt):
        return hashlib.scrypt(
            (code or '').encode('utf-8'),
            salt=(salt or '').encode('utf-8'),
            n=2 ** 14,
            r=8,
            p=1,
            dklen=32,
        ).hex()

    @api.model
    def _otp_code_length(self):
        return self.env["acpec.mobile.security.policy"].sudo().otp_code_length()
    @api.model
    def _otp_code_length(self):
        return self.env["acpec.mobile.security.policy"].sudo().otp_code_length()
    @api.model
    def _new_code(self):
        length = self._otp_code_length()
        return str(secrets.randbelow(10 ** length)).zfill(length)

    @api.model
    def _expiration_minutes(self):
        return self.env["acpec.mobile.security.policy"].sudo().otp_expiration_minutes()
    @api.model
    def _max_attempts(self):
        return self.env["acpec.mobile.security.policy"].sudo().otp_max_attempts()
    @api.model
    def _request_cooldown_seconds(self):
        return self.env["acpec.mobile.security.policy"].sudo().otp_request_cooldown_seconds()
    @api.model
    def _rate_limit_int(self, key, default):
        policy = self.env["acpec.mobile.security.policy"].sudo()
        specs = {
            "acpec_mobile_auth.otp_limit_identifier_per_minute": policy.OTP_LIMIT_IDENTIFIER_PER_MINUTE,
            "acpec_mobile_auth.otp_limit_identifier_per_day": policy.OTP_LIMIT_IDENTIFIER_PER_DAY,
            "acpec_mobile_auth.otp_limit_ip_per_hour": policy.OTP_LIMIT_IP_PER_HOUR,
            "acpec_mobile_auth.otp_limit_register_ip_per_day": policy.OTP_LIMIT_REGISTER_IP_PER_DAY,
        }
        spec = specs.get(key)
        if spec:
            return policy.get_int(spec)
        return policy.get_int_param(key, default, min_value=0)
    @api.model
    def _otp_limit_identifier_per_minute(self):
        return self._rate_limit_int('acpec_mobile_auth.otp_limit_identifier_per_minute', 1)

    @api.model
    def _otp_limit_identifier_per_day(self):
        return self._rate_limit_int('acpec_mobile_auth.otp_limit_identifier_per_day', 10)

    @api.model
    def _otp_limit_ip_per_hour(self):
        return self._rate_limit_int('acpec_mobile_auth.otp_limit_ip_per_hour', 30)

    @api.model
    def _otp_limit_register_ip_per_day(self):
        return self._rate_limit_int('acpec_mobile_auth.otp_limit_register_ip_per_day', 100)

    @api.model
    def _rate_limit_message(self):
        return _('Trop de demandes OTP. Veuillez réessayer plus tard.')

    @api.model
    def _mask_identifier(self, identifier):
        value = (identifier or '').strip()
        if len(value) <= 4:
            return '****' if value else ''
        return '%s****%s' % (value[:2], value[-2:])

    @api.model
    def _mask_ip(self, ip_address):
        value = (ip_address or '').strip()
        if not value:
            return ''
        if ':' in value:
            parts = value.split(':')
            return ':'.join(parts[:2] + ['****'])
        parts = value.split('.')
        if len(parts) == 4:
            return '.'.join(parts[:2] + ['*', '*'])
        return value[:3] + '****'

    @api.model
    def _log_rate_limit_refusal(self, *, scope, identifier=False, purpose=False, request_ip=False, limit=0):
        _logger.warning(
            'OTP rate-limit refusal scope=%s purpose=%s identifier=%s ip=%s limit=%s',
            scope,
            purpose or '',
            self._mask_identifier(identifier),
            self._mask_ip(request_ip),
            limit,
        )

    @api.model
    def _count_recent_otp(self, domain, since):
        return self.sudo().search_count(domain + [
            ('create_date', '>=', fields.Datetime.to_string(since)),
        ])

    @api.model
    def _check_request_rate_limits(self, identifier, purpose='login', request_ip=False):
        """Protect public OTP/SMS endpoints from abuse.

        Limits are enforced before creating/sending the OTP so a refused
        request never reaches the SMS provider. Messages returned to callers
        stay neutral; details are only written to server logs.
        """
        now = fields.Datetime.now()
        identifier = (identifier or '').strip()
        purpose = purpose or 'login'
        request_ip = (request_ip or '').strip()

        identifier_minute_limit = self._otp_limit_identifier_per_minute()
        if identifier_minute_limit > 0:
            minute_count = self._count_recent_otp(
                [('identifier', '=', identifier), ('purpose', '=', purpose)],
                now - relativedelta(minutes=1),
            )
            if minute_count >= identifier_minute_limit:
                self._log_rate_limit_refusal(
                    scope='identifier_per_minute',
                    identifier=identifier,
                    purpose=purpose,
                    request_ip=request_ip,
                    limit=identifier_minute_limit,
                )
                raise MobileAuthRateLimitError(self._rate_limit_message())

        identifier_day_limit = self._otp_limit_identifier_per_day()
        if identifier_day_limit > 0:
            day_count = self._count_recent_otp(
                [('identifier', '=', identifier), ('purpose', '=', purpose)],
                now - relativedelta(days=1),
            )
            if day_count >= identifier_day_limit:
                self._log_rate_limit_refusal(
                    scope='identifier_per_day',
                    identifier=identifier,
                    purpose=purpose,
                    request_ip=request_ip,
                    limit=identifier_day_limit,
                )
                raise MobileAuthRateLimitError(self._rate_limit_message())

        if request_ip:
            ip_hour_limit = self._otp_limit_ip_per_hour()
            if ip_hour_limit > 0:
                ip_hour_count = self._count_recent_otp(
                    [('request_ip', '=', request_ip)],
                    now - relativedelta(hours=1),
                )
                if ip_hour_count >= ip_hour_limit:
                    self._log_rate_limit_refusal(
                        scope='ip_per_hour',
                        identifier=identifier,
                        purpose=purpose,
                        request_ip=request_ip,
                        limit=ip_hour_limit,
                    )
                    raise MobileAuthRateLimitError(self._rate_limit_message())

            if purpose == 'register':
                register_ip_day_limit = self._otp_limit_register_ip_per_day()
                if register_ip_day_limit > 0:
                    register_ip_day_count = self._count_recent_otp(
                        [('request_ip', '=', request_ip), ('purpose', '=', 'register')],
                        now - relativedelta(days=1),
                    )
                    if register_ip_day_count >= register_ip_day_limit:
                        self._log_rate_limit_refusal(
                            scope='register_ip_per_day',
                            identifier=identifier,
                            purpose=purpose,
                            request_ip=request_ip,
                            limit=register_ip_day_limit,
                        )
                        raise MobileAuthRateLimitError(self._rate_limit_message())

    @api.model
    def _find_user(self, identifier):
        identifier = (identifier or '').strip()
        if not identifier:
            raise ValidationError(_('Identifiant requis.'))
        domain = ['|', '|', ('login', '=', identifier), ('mobile_phone', '=', identifier), ('email', '=', identifier)]
        user = self.env['res.users'].sudo().with_context(active_test=False).search(domain, limit=1)
        if not user:
            raise AccessError(_('Compte mobile introuvable.'))
        if getattr(user, 'mobile_state', False) == 'rejected':
            raise AccessError(_('Compte mobile rejeté.'))
        return user

    @api.model
    def request_otp(self, identifier, purpose='login', request_ip=False):
        purpose = purpose or 'login'
        if purpose not in ('login', 'register', 'reset'):
            raise ValidationError(_('Objet OTP invalide.'))
        identifier = (identifier or '').strip()
        if not identifier:
            raise ValidationError(_('Identifiant requis.'))

        # Gate public OTP requests before user/account lookup whenever the
        # identifier and purpose are known.  This rejects already-throttled
        # clients earlier and prevents needless database lookups.  This is
        # not an anti-enumeration mechanism by itself: requests that have
        # never created OTP rows still require uniform responses in a separate
        # hardening patch.
        self._check_request_rate_limits(identifier, purpose=purpose, request_ip=request_ip)

        user = False
        mobile_state = False
        is_station = False
        if purpose == 'register':
            if '@' in identifier:
                raise ValidationError(_('Registration OTP currently supports phone numbers only.'))
            user_domain = ['|', ('login', '=', identifier), ('mobile_phone', '=', identifier)]
            user = self.env['res.users'].sudo().with_context(active_test=False).search(user_domain, limit=1)
            if user:
                raise AccessError(_('Compte mobile déjà existant.'))
            pending_request = self.env['acpec.mobile.auth.account.request'].sudo().search([
                ('signup_identifier', '=', identifier),
                ('state', '=', 'pending'),
            ], limit=1)
            if pending_request:
                raise AccessError(_('Une demande de compte en attente existe déjà pour cet identifiant.'))
        else:
            user = self._find_user(identifier)
            try:
                is_station = user.has_group('acpec_fueltoken_base.group_fuel_station')
            except Exception:
                is_station = False
            mobile_state = getattr(user, 'mobile_state', False)
            if not user.active:
                raise AccessError(_('Compte mobile inactif.'))
            if not is_station and mobile_state not in (False, 'approved'):
                raise AccessError(_('Compte mobile non approuvé.'))
        now = fields.Datetime.now()
        self.sudo().search([
            ('identifier', '=', identifier),
            ('purpose', '=', purpose),
            ('state', '=', 'pending'),
        ]).write({'state': 'cancelled'})
        code = self._new_code()
        salt = secrets.token_urlsafe(16)
        challenge = self.sudo().create({
            'identifier': identifier,
            'mobile': user.mobile_phone or identifier,
            'email': user.email or False,
            'request_ip': request_ip or False,
            'user_id': user.id if user else False,
            'purpose': purpose,
            'salt': salt,
            'otp_hash': self._hash_otp(code, salt),
            'expires_at': now + relativedelta(minutes=self._expiration_minutes()),
            'max_attempts': self._max_attempts(),
            'state': 'pending',
        })
        challenge._send_otp_code(code)
        return challenge, code

    def _sms_recipient_phone(self):
        self.ensure_one()
        return self.mobile or self.user_id.mobile_phone or self.identifier

    def _sms_lang(self):
        self.ensure_one()
        candidate = self.user_id.lang or self.env.context.get('lang') or 'fr'
        candidate = (candidate or 'fr').strip().lower()
        return 'ar' if candidate.startswith('ar') else 'fr'

    def _sms_gateway_configured(self):
        params = self.env['ir.config_parameter'].sudo()
        provider = (
            params.get_param('SMS_PROVIDER')
            or os.getenv('SMS_PROVIDER')
            or 'chinguisoft'
        ).strip().lower()
        validation_key = (
            params.get_param('SMS_VALIDATION_KEY')
            or os.getenv('SMS_VALIDATION_KEY')
            or os.getenv('CHINGUI_SOFT_VALIDATION_KEY')
            or os.getenv('CHINGUISOFT_VALIDATION_KEY')
            or ''
        ).strip()
        token = (
            params.get_param('SMS_TOKEN')
            or os.getenv('SMS_TOKEN')
            or os.getenv('CHINGUI_SOFT_TOKEN')
            or os.getenv('CHINGUISOFT_TOKEN')
            or ''
        ).strip()
        return provider == 'chinguisoft' and bool(validation_key) and bool(token)

    @api.model
    def _otp_dev_mode(self):
        return self.env["acpec.mobile.security.policy"].sudo().otp_dev_mode_enabled()
    def _send_otp_code(self, code):
        self.ensure_one()
        phone = self._sms_recipient_phone()
        if not self._sms_gateway_configured():
            if self._otp_dev_mode():
                self.message_post(body=_('OTP pret pour %s (mode dev sans SMS).') % (phone or self.identifier,))
                return True
            raise ValidationError(_('La configuration SMS Chinguisoft est incomplete.'))
        sms_gateway = self.env['acpec.sms.gateway'].sudo()
        sms_gateway.send_validation_sms(phone, code=code, lang=self._sms_lang())
        self.message_post(body=_('OTP envoye par SMS pour %s.') % (phone or self.identifier,))
        return True

    def verify(self, code):
        self.ensure_one()
        now = fields.Datetime.now()
        if self.state != 'pending':
            raise ValidationError(_("Ce challenge OTP n'est plus actif."))
        if self.blocked_until and self.blocked_until > now:
            raise AccessError(_('Ce challenge OTP est temporairement bloqué.'))
        if self.expires_at and self.expires_at <= now:
            self.write({'state': 'expired'})
            raise ValidationError(_('Le code OTP a expiré.'))
        code = (code or '').strip()
        expected_length = self._otp_code_length()
        if not code or not code.isdigit() or len(code) != expected_length:
            raise ValidationError(
                _('Le code OTP doit contenir exactement %s chiffres.') % expected_length
            )
        expected_hash = self.otp_hash or ''
        given_hash = self._hash_otp(code, self.salt) or ''
        if not hmac.compare_digest(given_hash, expected_hash):
            attempt_count = self.attempt_count + 1
            vals = {'attempt_count': attempt_count}
            if attempt_count >= self.max_attempts:
                vals.update({
                    'state': 'blocked',
                    'blocked_until': now + relativedelta(minutes=15),
                })
            self.write(vals)
            raise AccessError(_('Code OTP invalide.'))
        self.write({
            'state': 'verified',
            'verified_at': now,
        })
        return self.user_id

