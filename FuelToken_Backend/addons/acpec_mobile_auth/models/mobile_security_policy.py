import os

from odoo import api, models
from odoo.tools import config


class AcpecMobileSecurityPolicy(models.AbstractModel):
    _name = "acpec.mobile.security.policy"
    _description = "ACPEC Mobile Security Policy"

    ACCESS_TOKEN_MINUTES = ("acpec_mobile_auth.access_token_minutes", 15, 5, 60)
    REFRESH_TOKEN_DAYS = ("acpec_mobile_auth.refresh_token_days", 30, 1, 90)
    REFRESH_TOKEN_GRACE_SECONDS = ("acpec_mobile_auth.refresh_token_grace_seconds", 30, 0, 120)

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

    # Legacy setting key kept only so readiness can detect stale configuration.
    # It is never a source of truth for dev relax after Patch36A.
    OTP_DEV_MODE_KEY = "acpec_mobile_auth.otp_dev_mode"

    DEV_MODE_ENV_KEY = "ACPEC_FUELTOKEN_DEV_MODE"
    LEGACY_TEST_MODE_ENV_KEY = "ACPEC_FUELTOKEN_TEST_MODE"

    RUNTIME_ENV_KEYS = ("ACPEC_ENV", "ODOO_ENV", "ENV")
    ODOO_CONFIG_ENV_KEY = "acpec_env"

    ENV_LABEL_PRODUCTION = "PRODUCTION"
    ENV_LABEL_DEV_LIKE = "DEV_LIKE"
    ENV_LABEL_UNKNOWN = "UNKNOWN"

    DEV_ENV_VALUES = ("local", "dev", "test")
    PRODUCTION_ENV_VALUES = ("prod", "production")
    TRUE_VALUES = ("1", "true", "yes", "y", "on")

    @api.model
    def _is_truthy(self, value):
        if value is True:
            return True
        if value in (False, None, ""):
            return False
        return str(value).strip().casefold() in self.TRUE_VALUES

    @api.model
    def _env_bool(self, key):
        return self._is_truthy(os.getenv(key))

    @api.model
    def _config_value(self, key):
        try:
            return config.get(key)
        except Exception:
            try:
                return config[key]
            except Exception:
                return None

    @api.model
    def _normalize_env_value(self, value):
        return str(value or "").strip().casefold()

    @api.model
    def _classify_env_value(self, value):
        normalized = self._normalize_env_value(value)
        if not normalized:
            return "absent", normalized
        if normalized in self.PRODUCTION_ENV_VALUES:
            return "production", normalized
        if normalized in self.DEV_ENV_VALUES:
            return "dev_like", normalized
        return "unknown", normalized

    @api.model
    def runtime_env_sources(self):
        """Return explicit runtime environment signals, normalized.

        OS variables are considered first. Odoo config is considered only when
        no OS runtime environment variable is defined.

        No ir.config_parameter lookup is used for runtime classification.
        """
        sources = []
        for priority, key in enumerate(self.RUNTIME_ENV_KEYS, start=1):
            raw = os.getenv(key)
            if raw in (None, ""):
                continue
            kind, normalized = self._classify_env_value(raw)
            sources.append({
                "source": "os",
                "key": key,
                "priority": priority,
                "raw": str(raw),
                "normalized": normalized,
                "kind": kind,
            })

        if sources:
            return sources

        raw = self._config_value(self.ODOO_CONFIG_ENV_KEY)
        if raw not in (None, ""):
            kind, normalized = self._classify_env_value(raw)
            sources.append({
                "source": "odoo_config",
                "key": self.ODOO_CONFIG_ENV_KEY,
                "priority": 4,
                "raw": str(raw),
                "normalized": normalized,
                "kind": kind,
            })
        return sources

    @api.model
    def runtime_env_label(self):
        """Return PRODUCTION, DEV_LIKE or UNKNOWN.

        Fail-closed:
        - no environment defaults to PRODUCTION/strict;
        - any prod-like signal wins over any dev-like signal;
        - any unknown explicit signal is UNKNOWN/strict unless prod-like exists.
        """
        sources = self.runtime_env_sources()
        if not sources:
            return self.ENV_LABEL_PRODUCTION
        if any(source["kind"] == "production" for source in sources):
            return self.ENV_LABEL_PRODUCTION
        if any(source["kind"] == "unknown" for source in sources):
            return self.ENV_LABEL_UNKNOWN
        if any(source["kind"] == "dev_like" for source in sources):
            return self.ENV_LABEL_DEV_LIKE
        return self.ENV_LABEL_PRODUCTION

    @api.model
    def runtime_has_concurrent_prod_dev_signal(self):
        sources = self.runtime_env_sources()
        return bool(
            any(source["kind"] == "production" for source in sources)
            and any(source["kind"] == "dev_like" for source in sources)
        )

    @api.model
    def runtime_dev_mode_flag_enabled(self):
        return self._env_bool(self.DEV_MODE_ENV_KEY)

    @api.model
    def runtime_legacy_test_mode_present(self):
        return os.getenv(self.LEGACY_TEST_MODE_ENV_KEY) not in (None, "")

    @api.model
    def runtime_odoo_test_enable_enabled(self):
        return self._is_truthy(self._config_value("test_enable"))

    @api.model
    def runtime_acpec_env_is_test(self):
        return self._normalize_env_value(os.getenv("ACPEC_ENV")) == "test"

    @api.model
    def runtime_allows_dev_relax(self):
        return (
            self.runtime_env_label() == self.ENV_LABEL_DEV_LIKE
            and self.runtime_dev_mode_flag_enabled()
        )

    @api.model
    def otp_dev_runtime_allowed(self):
        """Compatibility alias: all dev relax now passes through one gate."""
        return self.runtime_allows_dev_relax()

    @api.model
    def _raise_if_test_mode_forbidden_in_production(self):
        """Compatibility no-op.

        Patch36A does not hard-crash Odoo for dev flag mistakes.
        The system remains strict by default and readiness reports critical
        configuration problems.
        """
        return False

    @api.model
    def _get_param(self, key):
        """Read only the dedicated mobile security settings table.

        ir.config_parameter is legacy and is not a runtime source for mobile
        security parameters after Patch36A.
        """
        return self.env["acpec.mobile.security.setting"].sudo().get_active_value(key)

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
    def get_otp_antiflood_int(self, spec):
        """Return OTP anti-flood value with fail-closed handling.

        In dev relax, anti-flood is disabled by policy without any DB mutation.
        In strict mode, zero/negative setting values fall back to safe defaults.
        """
        key, default, _min_value, _max_value = spec
        if self.runtime_allows_dev_relax():
            return 0
        value = self.get_int(spec)
        if value <= 0:
            return default
        return value

    @api.model
    def get_bool(self, key, default=False):
        raw = self._get_param(key)
        if raw in (False, None, ""):
            return bool(default)
        return str(raw).strip().casefold() in ("1", "true", "yes", "y", "on")

    @api.model
    def access_token_minutes(self):
        return self.get_int(self.ACCESS_TOKEN_MINUTES)

    @api.model
    def refresh_token_days(self):
        return self.get_int(self.REFRESH_TOKEN_DAYS)

    @api.model
    def refresh_token_grace_seconds(self):
        return self.get_int(self.REFRESH_TOKEN_GRACE_SECONDS)

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
        return self.get_otp_antiflood_int(self.OTP_REQUEST_COOLDOWN_SECONDS)

    @api.model
    def otp_limit_identifier_per_minute(self):
        return self.get_otp_antiflood_int(self.OTP_LIMIT_IDENTIFIER_PER_MINUTE)

    @api.model
    def otp_limit_identifier_per_day(self):
        return self.get_otp_antiflood_int(self.OTP_LIMIT_IDENTIFIER_PER_DAY)

    @api.model
    def otp_limit_ip_per_hour(self):
        return self.get_otp_antiflood_int(self.OTP_LIMIT_IP_PER_HOUR)

    @api.model
    def otp_limit_register_ip_per_day(self):
        return self.get_otp_antiflood_int(self.OTP_LIMIT_REGISTER_IP_PER_DAY)

    @api.model
    def otp_dev_mode_enabled(self):
        """OTP dev mode is the unified Patch36A runtime dev relax gate."""
        return self.runtime_allows_dev_relax()
