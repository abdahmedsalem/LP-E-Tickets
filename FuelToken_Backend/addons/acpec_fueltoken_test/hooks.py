def post_init_hook(env):
    params = env['ir.config_parameter'].sudo()
    params.set_param('acpec_mobile_auth.otp_dev_mode', 'True')
    params.set_param('acpec_mobile_auth.otp_request_cooldown_seconds', '0')


def uninstall_hook(env):
    params = env['ir.config_parameter'].sudo()
    params.set_param('acpec_mobile_auth.otp_dev_mode', 'False')
    params.set_param('acpec_mobile_auth.otp_request_cooldown_seconds', '60')
