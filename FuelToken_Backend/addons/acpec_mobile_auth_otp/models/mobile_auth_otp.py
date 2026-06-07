import hashlib
import os
import secrets

from dateutil.relativedelta import relativedelta

from odoo import _, api, fields, models
from odoo.exceptions import AccessError, ValidationError


class AcpecMobileAuthOtp(models.Model):
    _name = 'acpec.mobile.auth.otp'
    _description = 'ACPEC Mobile OTP Challenge'
    _inherit = ['mail.thread', 'mail.activity.mixin']
    _order = 'create_date desc, id desc'

    name = fields.Char(default='New', readonly=True, copy=False, index=True)
    identifier = fields.Char(required=True, index=True)
    mobile = fields.Char(index=True)
    email = fields.Char(index=True)
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
    def _new_code(self):
        return str(secrets.randbelow(1000000)).zfill(6)

    @api.model
    def _expiration_minutes(self):
        value = self.env['ir.config_parameter'].sudo().get_param('acpec_mobile_auth.otp_expiration_minutes')
        try:
            return int(value or 5)
        except Exception:
            return 5

    @api.model
    def _max_attempts(self):
        value = self.env['ir.config_parameter'].sudo().get_param('acpec_mobile_auth.otp_max_attempts')
        try:
            return int(value or 5)
        except Exception:
            return 5

    @api.model
    def _request_cooldown_seconds(self):
        value = self.env['ir.config_parameter'].sudo().get_param(
            'acpec_mobile_auth.otp_request_cooldown_seconds'
        )
        try:
            return max(0, int(value or 60))
        except Exception:
            return 60

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
    def request_otp(self, identifier, purpose='login'):
        purpose = purpose or 'login'
        if purpose not in ('login', 'register', 'reset'):
            raise ValidationError(_('Objet OTP invalide.'))
        user = False
        mobile_state = False
        is_station = False
        if purpose == 'register':
            identifier = (identifier or '').strip()
            if not identifier:
                raise ValidationError(_('Identifiant requis.'))
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
        cooldown_seconds = self._request_cooldown_seconds()
        if cooldown_seconds > 0:
            cutoff = now - relativedelta(seconds=cooldown_seconds)
            recent = self.sudo().search([
                ('identifier', '=', identifier),
                ('purpose', '=', purpose),
                ('state', '=', 'pending'),
                ('create_date', '>=', fields.Datetime.to_string(cutoff)),
            ], limit=1)
            if recent:
                raise ValidationError(
                    _('Veuillez patienter %ds avant de redemander un OTP.') % cooldown_seconds
                )
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

    def _otp_dev_mode(self):
        return bool(self.env['ir.config_parameter'].sudo().get_param('acpec_mobile_auth.otp_dev_mode'))

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
        if not code or not code.isdigit() or len(code) != 6:
            raise ValidationError(_('Le code OTP doit contenir exactement 6 chiffres.'))
        if self._hash_otp(code, self.salt) != self.otp_hash:
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
