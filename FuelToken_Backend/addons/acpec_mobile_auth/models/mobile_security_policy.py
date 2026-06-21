from odoo import api, models


class AcpecMobileSecurityPolicy(models.AbstractModel):
    _name = "acpec.mobile.security.policy"
    _description = "ACPEC Mobile Security Policy"

    ACCESS_TOKEN_MINUTES = ("acpec_mobile_auth.access_token_minutes", 15, 5, 60)
    REFRESH_TOKEN_DAYS = ("acpec_mobile_auth.refresh_token_days", 30, 1, 90)

    MOBILE_PIN_LOCK_SECONDS = ("acpec_mobile_auth.mobile_pin_lock_seconds", 60, 30, 3600)
    MOBILE_PIN_MAX_ATTEMPTS = ("acpec_mobile_auth.mobile_pin_max_attempts", 5, 1, 10)
    MOBILE_PIN_HARD_BLOCK_ATTEMPTS = ("acpec_mobile_auth.mobile_pin_hard_block_attempts", 20, 10, 100)

    OTP_CODE_LENGTH = ("acpec_mobile_auth.otp_code_length", 6, 4, 8)
    OTP_EXPIRATION_MINUTES = ("acpec_mobile_auth.otp_expiration_minutes", 5, 1, 30)
    OTP_MAX_ATTEMPTS = ("acpec_mobile_auth.otp_max_attempts", 5, 1, 10)
    OTP_REQUEST_COOLDOWN_SECONDS = ("acpec_mobile_auth.otp_request_cooldown_seconds", 60, 0, 3600)

    OTP_LIMIT_IDENTIFIER_PER_MINUTE = ("acpec_mobile_auth.otp_limit_identifier_per_minute", 1, 0, 20)
    OTP_LIMIT_IDENTIFIER_PER_DAY = ("acpec_mobile_auth.otp_limit_identifier_per_day", 10, 0, 100)
    OTP_LIMIT_IP_PER_HOUR = ("acpec_mobile_auth.otp_limit_ip_per_hour", 30, 0, 500)
    OTP_LIMIT_REGISTER_IP_PER_DAY = ("acpec_mobile_auth.otp_limit_register_ip_per_day", 100, 0, 1000)

    OTP_DEV_MODE_KEY = "acpec_mobile_auth.otp_dev_mode"

    @api.model
    def _get_param(self, key):
        return self.env["ir.config_parameter"].sudo().get_param(key)

    @api.model
    def get_int_param(self, key, default, min_value=None, max_value=None):
        raw = self._get_param(key)
        try:
            value = int(raw if raw not in (False, None, "") else default)
        except Exception:
            value = default

        if min_value is not None:
            value = max(min_value, value)
        if max_value is not None:
            value = min(max_value, value)
        return value

    @api.model
    def get_int(self, spec):
        key, default, min_value, max_value = spec
        return self.get_int_param(key, default, min_value=min_value, max_value=max_value)

    @api.model
    def get_bool(self, key, default=False):
        raw = self._get_param(key)
        if raw in (False, None, ""):
            return bool(default)
        return str(raw).strip().lower() in ("1", "true", "yes", "y", "on")

    @api.model
    def access_token_minutes(self):
        return self.get_int(self.ACCESS_TOKEN_MINUTES)

    @api.model
    def refresh_token_days(self):
        return self.get_int(self.REFRESH_TOKEN_DAYS)

    @api.model
    def mobile_pin_lock_seconds(self):
        return self.get_int(self.MOBILE_PIN_LOCK_SECONDS)

    @api.model
    def mobile_pin_max_attempts(self):
        return self.get_int(self.MOBILE_PIN_MAX_ATTEMPTS)

    @api.model
    def mobile_pin_hard_block_attempts(self):
        return self.get_int(self.MOBILE_PIN_HARD_BLOCK_ATTEMPTS)

    @api.model
    def otp_code_length(self):
        return self.get_int(self.OTP_CODE_LENGTH)

    @api.model
    def otp_expiration_minutes(self):
        return self.get_int(self.OTP_EXPIRATION_MINUTES)

    @api.model
    def otp_max_attempts(self):
        return self.get_int(self.OTP_MAX_ATTEMPTS)

    @api.model
    def otp_request_cooldown_seconds(self):
        return self.get_int(self.OTP_REQUEST_COOLDOWN_SECONDS)

    @api.model
    def otp_limit_identifier_per_minute(self):
        return self.get_int(self.OTP_LIMIT_IDENTIFIER_PER_MINUTE)

    @api.model
    def otp_limit_identifier_per_day(self):
        return self.get_int(self.OTP_LIMIT_IDENTIFIER_PER_DAY)

    @api.model
    def otp_limit_ip_per_hour(self):
        return self.get_int(self.OTP_LIMIT_IP_PER_HOUR)

    @api.model
    def otp_limit_register_ip_per_day(self):
        return self.get_int(self.OTP_LIMIT_REGISTER_IP_PER_DAY)

    @api.model
    def otp_dev_mode_enabled(self):
        return self.get_bool(self.OTP_DEV_MODE_KEY, default=False)
