from odoo import _, api, fields, models
from odoo.exceptions import ValidationError


class AcpecMobileAuthOtp(models.Model):
    _inherit = 'acpec.mobile.auth.otp'

    GOOGLE_PLAY_REVIEW_CONTEXT = 'acpec_google_play_review_otp'
    GOOGLE_PLAY_REVIEW_ENABLED_PARAM = (
        'acpec_google_play_review_access.enabled'
    )
    GOOGLE_PLAY_REVIEW_PHONE_PARAM = (
        'acpec_google_play_review_access.phone'
    )
    GOOGLE_PLAY_REVIEW_OTP = '000000'

    @api.model
    def _normalize_google_play_review_phone(self, value):
        digits = ''.join(char for char in str(value or '') if char.isdigit())
        if len(digits) == 11 and digits.startswith('222'):
            digits = digits[3:]
        return digits

    @api.model
    def _google_play_review_enabled(self):
        value = self.env['ir.config_parameter'].sudo().get_param(
            self.GOOGLE_PLAY_REVIEW_ENABLED_PARAM
        )
        return str(value or '').strip().casefold() in {
            '1',
            'true',
            'yes',
            'on',
        }

    @api.model
    def _is_google_play_review_login(self, identifier, purpose):
        if purpose != 'login' or not self._google_play_review_enabled():
            return False
        params = self.env['ir.config_parameter'].sudo()
        raw_phones = params.get_param(self.GOOGLE_PLAY_REVIEW_PHONE_PARAM) or ''
        configured_phones = {
            self._normalize_google_play_review_phone(value)
            for value in raw_phones.replace(';', ',').split(',')
        }
        configured_phones.discard('')
        requested_phone = self._normalize_google_play_review_phone(identifier)
        return requested_phone in configured_phones

    @api.model
    def request_otp(self, identifier, purpose='login', request_ip=False):
        is_review_login = self._is_google_play_review_login(
            identifier,
            purpose,
        )
        otp_model = self.with_context(
            **{self.GOOGLE_PLAY_REVIEW_CONTEXT: is_review_login}
        )
        return super(AcpecMobileAuthOtp, otp_model).request_otp(
            identifier,
            purpose=purpose,
            request_ip=request_ip,
        )

    @api.model
    def _new_code(self):
        if self.env.context.get(self.GOOGLE_PLAY_REVIEW_CONTEXT):
            return self.GOOGLE_PLAY_REVIEW_OTP
        return super()._new_code()

    def _send_otp_code(self, code):
        self.ensure_one()
        if self.env.context.get(self.GOOGLE_PLAY_REVIEW_CONTEXT):
            self.sudo().message_post(
                body=_('Challenge Google Play cree sans envoi de SMS.')
            )
            return True
        return super()._send_otp_code(code)

    @api.model
    def _otp_dev_mode(self):
        if len(self) == 1 and self._is_google_play_review_login(
            self.identifier,
            self.purpose,
        ):
            return True
        return super()._otp_dev_mode()


class ResConfigSettings(models.TransientModel):
    _inherit = 'res.config.settings'

    google_play_review_enabled = fields.Boolean(
        string='Activer le compte de demonstration Google Play',
        config_parameter='acpec_google_play_review_access.enabled',
    )
    google_play_review_phone = fields.Char(
        string='Numeros Google Play autorises',
        config_parameter='acpec_google_play_review_access.phone',
    )

    def set_values(self):
        for wizard in self:
            if not wizard.google_play_review_enabled:
                continue
            otp_model = self.env['acpec.mobile.auth.otp']
            phones = []
            for value in (
                wizard.google_play_review_phone or ''
            ).replace(';', ',').split(','):
                phone = otp_model._normalize_google_play_review_phone(value)
                if len(phone) != 8 or phone[0] not in {'2', '3', '4'}:
                    raise ValidationError(_(
                        'Chaque numero Google Play doit contenir 8 chiffres '
                        'et commencer par 2, 3 ou 4.'
                    ))
                if phone not in phones:
                    phones.append(phone)
            wizard.google_play_review_phone = ','.join(phones)
        return super().set_values()
