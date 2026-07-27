from odoo import models


class AcpecMobileAuthOtp(models.Model):
    _inherit = 'acpec.mobile.auth.otp'

    # Patch36A:
    # No OTP override here. Dev OTP belongs to acpec_mobile_auth_otp and is
    # gated by acpec.mobile.security.policy.runtime_allows_dev_relax().
    pass
