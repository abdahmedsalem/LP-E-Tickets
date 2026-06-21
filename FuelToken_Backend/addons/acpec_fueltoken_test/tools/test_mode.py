import os


_TRUE_VALUES = {'1', 'true', 'yes', 'on', 'dev', 'test'}
_RUNTIME_ENV_KEYS = ('ACPEC_ENV', 'ODOO_ENV', 'ENV')
_PRODUCTION_ENV_VALUES = {'prod', 'production'}


def _env_bool(key):
    return (os.getenv(key) or '').strip().lower() in _TRUE_VALUES


def is_production_runtime():
    return any(
        (os.getenv(key) or '').strip().lower() in _PRODUCTION_ENV_VALUES
        for key in _RUNTIME_ENV_KEYS
    )


def is_fueltoken_test_mode_enabled():
    """Return True only when the local FuelToken test module is explicitly enabled.

    This module contains dangerous local-test behavior: fixed OTP, disabled SMS
    sending and a public browser test console. The mere fact that the module is
    installed must never activate those behaviors in production.
    """
    enabled = _env_bool('ACPEC_FUELTOKEN_TEST_MODE')
    if enabled and is_production_runtime():
        raise RuntimeError(
            'ACPEC_FUELTOKEN_TEST_MODE is forbidden when runtime environment is production.'
        )
    return enabled
