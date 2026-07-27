from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestMobileSecuritySettingsMigration(TransactionCase):

    def setUp(self):
        super().setUp()
        self.settings = self.env['acpec.mobile.security.setting'].sudo()
        self.icp = self.env['ir.config_parameter'].sudo()

    def _clear_setting(self, key):
        self.settings.search([('key', '=', key)]).unlink()

    def test_migrate_copies_existing_icp_when_setting_absent(self):
        key = 'acpec_mobile_auth.mobile_pin_max_attempts'
        self._clear_setting(key)
        self.icp.set_param(key, '8')

        migrated = self.settings._migrate_from_ir_config_parameter()

        record = self.settings.search([('key', '=', key)], limit=1)
        self.assertGreaterEqual(migrated, 1)
        self.assertTrue(record)
        self.assertTrue(record.active)
        self.assertEqual(record.value, '8')
        self.assertEqual(
            self.icp.get_param(key),
            '8',
            'Legacy ICP value must remain in place during Patch29C.',
        )

    def test_migrate_does_not_override_existing_setting(self):
        key = 'acpec_mobile_auth.mobile_pin_max_attempts'
        self._clear_setting(key)
        self.icp.set_param(key, '8')
        record = self.settings.create({
            'key': key,
            'value': '6',
            'active': True,
            'note': 'Manual override',
        })

        self.settings._migrate_from_ir_config_parameter()

        record.invalidate_recordset(['value', 'active', 'note'])
        self.assertEqual(record.value, '6')
        self.assertEqual(record.note, 'Manual override')

    def test_migrate_is_idempotent(self):
        key = 'acpec_mobile_auth.refresh_token_grace_seconds'
        self._clear_setting(key)
        self.icp.set_param(key, '45')

        first = self.settings._migrate_from_ir_config_parameter()
        second = self.settings._migrate_from_ir_config_parameter()

        records = self.settings.search([('key', '=', key)])
        self.assertGreaterEqual(first, 1)
        self.assertEqual(second, 0)
        self.assertEqual(len(records), 1)
        self.assertEqual(records.value, '45')

    def test_migrate_skips_sms_settings(self):
        self.icp.set_param('SMS_PROVIDER', 'chinguisoft')
        self.icp.set_param('SMS_VALIDATION_KEY', 'secret-validation-key')
        self.icp.set_param('SMS_TOKEN', 'secret-token')

        self.settings._migrate_from_ir_config_parameter()

        sms_like_records = self.settings.search([('key', 'ilike', 'SMS')])
        self.assertFalse(sms_like_records)
