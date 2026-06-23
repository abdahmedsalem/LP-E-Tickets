import os


_TRUE_VALUES = {'1', 'true', 'yes', 'y', 'on'}
_RUNTIME_ENV_KEYS = ('ACPEC_ENV', 'ODOO_ENV', 'ENV')
_DEV_ENV_VALUES = {'local', 'dev', 'test'}
_PRODUCTION_ENV_VALUES = {'prod', 'production'}


def _normalize(value):
    return str(value or '').strip().casefold()


def _env_bool(key):
    return _normalize(os.getenv(key)) in _TRUE_VALUES


def runtime_env_label():
    values = [
        _normalize(os.getenv(key))
        for key in _RUNTIME_ENV_KEYS
        if os.getenv(key) not in (None, '')
    ]
    if not values:
        return 'PRODUCTION'
    if any(value in _PRODUCTION_ENV_VALUES for value in values):
        return 'PRODUCTION'
    if any(value not in _DEV_ENV_VALUES for value in values):
        return 'UNKNOWN'
    if any(value in _DEV_ENV_VALUES for value in values):
        return 'DEV_LIKE'
    return 'PRODUCTION'


def is_production_runtime():
    return runtime_env_label() == 'PRODUCTION'


def is_fueltoken_test_mode_enabled():
    """Console availability helper only; does not define security policy.

    Patch36A removes the legacy test flag from the security path.
    The legacy console is available only when the same explicit dev gate is open:
    ACPEC_ENV/ODOO_ENV/ENV in local/dev/test + ACPEC_FUELTOKEN_DEV_MODE=1.
    """
    return runtime_env_label() == 'DEV_LIKE' and _env_bool('ACPEC_FUELTOKEN_DEV_MODE')
