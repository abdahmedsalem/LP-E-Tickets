from dateutil.relativedelta import relativedelta

from odoo import _, fields, models
from odoo.exceptions import AccessError, ValidationError

from ..tools import is_fueltoken_test_mode_enabled


LOCAL_TEST_OTP_CODE = '000000'


class AcpecMobileAuthOtp(models.Model):
    _inherit = 'acpec.mobile.auth.otp'

    def _new_code(self):
        if not is_fueltoken_test_mode_enabled():
            return super()._new_code()
        return LOCAL_TEST_OTP_CODE

    def _send_otp_code(self, code):
        if not is_fueltoken_test_mode_enabled():
            return super()._send_otp_code(code)

        for challenge in self:
            phone = challenge._sms_recipient_phone()
            challenge.message_post(
                body=_('OTP local de test pret pour %s : %s. Aucun SMS envoye.') % (
                    phone or challenge.identifier,
                    LOCAL_TEST_OTP_CODE,
                )
            )
        return True

    def verify(self, code):
        if not is_fueltoken_test_mode_enabled():
            return super().verify(code)

        # Module de test uniquement : accepter l'OTP local a 6 chiffres 000000.
        # Les endpoints appeles restent les endpoints reels de production.
        self.ensure_one()
        now = fields.Datetime.now()
        if self.state != 'pending':
            raise ValidationError(_("Ce challenge OTP n'est plus actif."))
        if self.blocked_until and self.blocked_until > now:
            raise AccessError(_('Ce challenge OTP est temporairement bloque.'))
        if self.expires_at and self.expires_at <= now:
            self.write({'state': 'expired'})
            raise ValidationError(_('Le code OTP a expire.'))

        code = (code or '').strip()
        if not code or not code.isdigit():
            raise ValidationError(_('Le code OTP doit contenir uniquement des chiffres.'))

        if code != LOCAL_TEST_OTP_CODE:
            attempt_count = self.attempt_count + 1
            vals = {'attempt_count': attempt_count}
            if attempt_count >= self.max_attempts:
                vals.update({
                    'state': 'blocked',
                    'blocked_until': now + relativedelta(minutes=15),
                })
            self.write(vals)
            raise AccessError(_('Code OTP invalide.'))

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
