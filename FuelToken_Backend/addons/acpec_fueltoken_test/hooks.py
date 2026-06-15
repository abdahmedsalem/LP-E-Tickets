from .tools import is_fueltoken_test_mode_enabled


def post_init_hook(env):
    params = env['ir.config_parameter'].sudo()

    if not is_fueltoken_test_mode_enabled():
        # Safety default: installing this local test module must never enable
        # OTP dev mode unless ACPEC_FUELTOKEN_TEST_MODE is explicitly enabled.
        params.set_param('acpec_mobile_auth.otp_dev_mode', 'False')
        params.set_param('acpec_mobile_auth.otp_request_cooldown_seconds', '60')
        return

    params.set_param('acpec_mobile_auth.otp_dev_mode', 'True')
    params.set_param('acpec_mobile_auth.otp_request_cooldown_seconds', '0')


def uninstall_hook(env):
    params = env['ir.config_parameter'].sudo()
    params.set_param('acpec_mobile_auth.otp_dev_mode', 'False')
    params.set_param('acpec_mobile_auth.otp_request_cooldown_seconds', '60')
