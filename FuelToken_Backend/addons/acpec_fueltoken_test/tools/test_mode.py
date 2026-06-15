import os


_TRUE_VALUES = {'1', 'true', 'yes', 'on', 'dev', 'test'}


def is_fueltoken_test_mode_enabled():
    """Return True only when the local FuelToken test module is explicitly enabled.

    This module contains dangerous local-test behavior: fixed OTP, disabled SMS
    sending and a public browser test console. The mere fact that the module is
    installed must never activate those behaviors in production.
    """
    return (os.getenv('ACPEC_FUELTOKEN_TEST_MODE') or '').strip().lower() in _TRUE_VALUES
