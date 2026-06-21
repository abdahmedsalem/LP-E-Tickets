from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestOtpResConfigSettingsSecurityTable(TransactionCase):

    def setUp(self):
        super().setUp()
        self.settings_model = self.env['res.config.settings'].sudo()
        self.security_settings = self.env['acpec.mobile.security.setting'].sudo()
        self.icp = self.env['ir.config_parameter'].sudo()

    def _clear_setting(self, key):
        self.security_settings.search([('key', '=', key)]).unlink()

    def test_otp_rate_limit_settings_read_from_policy_with_icp_fallback(self):
        key = 'acpec_mobile_auth.otp_limit_identifier_per_minute'
        self._clear_setting(key)
        self.icp.set_param(key, '7')

        values = self.settings_model.get_values()

        self.assertEqual(values['otp_limit_identifier_per_minute'], 7)

    def test_otp_rate_limit_settings_write_to_dedicated_table(self):
        keys = [
            'acpec_mobile_auth.otp_limit_identifier_per_minute',
            'acpec_mobile_auth.otp_limit_identifier_per_day',
            'acpec_mobile_auth.otp_limit_ip_per_hour',
            'acpec_mobile_auth.otp_limit_register_ip_per_day',
        ]
        for key in keys:
            self._clear_setting(key)

        wizard = self.settings_model.create({
            'otp_limit_identifier_per_minute': 2,
            'otp_limit_identifier_per_day': 22,
            'otp_limit_ip_per_hour': 33,
            'otp_limit_register_ip_per_day': 44,
        })
        wizard.set_values()

        expected = {
            'acpec_mobile_auth.otp_limit_identifier_per_minute': '2',
            'acpec_mobile_auth.otp_limit_identifier_per_day': '22',
            'acpec_mobile_auth.otp_limit_ip_per_hour': '33',
            'acpec_mobile_auth.otp_limit_register_ip_per_day': '44',
        }
        for key, value in expected.items():
            record = self.security_settings.search([('key', '=', key)], limit=1)
            self.assertTrue(record)
            self.assertTrue(record.active)
            self.assertEqual(record.value, value)

    def test_sms_settings_still_use_icp(self):
        wizard = self.settings_model.create({
            'sms_provider': 'chinguisoft',
            'sms_validation_key': 'ui-validation-key',
            'sms_token': 'ui-token',
            'sms_url': 'https://chinguisoft.com/api/sms/validation',
            'sms_default_lang': 'fr',
        })
        wizard.set_values()

        self.assertEqual(self.icp.get_param('SMS_PROVIDER'), 'chinguisoft')
        self.assertEqual(self.icp.get_param('SMS_VALIDATION_KEY'), 'ui-validation-key')
        self.assertEqual(self.icp.get_param('SMS_TOKEN'), 'ui-token')
        self.assertEqual(self.icp.get_param('SMS_URL'), 'https://chinguisoft.com/api/sms/validation')
        self.assertEqual(self.icp.get_param('SMS_DEFAULT_LANG'), 'fr')
