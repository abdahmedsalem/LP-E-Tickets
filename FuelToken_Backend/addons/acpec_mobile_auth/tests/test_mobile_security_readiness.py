import os
from contextlib import ExitStack
from unittest.mock import patch


def _acpec_test_mobile_phone(label):
    """Return a deterministic canonical 8-digit mobile phone for test labels."""
    value = 2166136261
    for char in str(label):
        value ^= ord(char)
        value = (value * 16777619) % 10000000
    return "3%07d" % value

from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestMobileSecurityReadiness(TransactionCase):

    def setUp(self):
        super().setUp()
        self.readiness = self.env['acpec.mobile.security.readiness'].sudo()
        self.settings = self.env['acpec.mobile.security.setting'].sudo()
        self.keys = [
            'acpec_mobile_auth.otp_dev_mode',
            'acpec_mobile_auth.otp_request_cooldown_seconds',
            'acpec_mobile_auth.otp_limit_identifier_per_minute',
            'acpec_mobile_auth.otp_limit_identifier_per_day',
            'acpec_mobile_auth.otp_limit_ip_per_hour',
            'acpec_mobile_auth.otp_limit_register_ip_per_day',
        ]
        self.settings.search([('key', 'in', self.keys)]).unlink()
        self._ensure_single_fueltoken_company()

    def _ensure_single_fueltoken_company(self):
        Company = self.env['res.company'].sudo()
        if 'acpec_fueltoken_enabled' not in Company._fields:
            return False
        Company.search([
            ('acpec_fueltoken_enabled', '=', True),
            ('id', '!=', self.env.company.id),
        ]).write({'acpec_fueltoken_enabled': False})
        self.env.company.sudo().write({'acpec_fueltoken_enabled': True})
        return self.env.company.sudo()

    def _runtime_env(self, acpec_env, dev_mode='', legacy_test_mode=''):
        return {
            'ACPEC_ENV': acpec_env,
            'ODOO_ENV': '',
            'ENV': '',
            'ACPEC_FUELTOKEN_DEV_MODE': dev_mode,
            'ACPEC_FUELTOKEN_TEST_MODE': legacy_test_mode,
        }

    def _sms_env(self, validation_key='', token='', provider='chinguisoft', url=''):
        return {
            'SMS_PROVIDER': provider,
            'SMS_URL': url,
            'CHINGUISOFT_URL': '',
            'SMS_VALIDATION_KEY': validation_key,
            'CHINGUI_SOFT_VALIDATION_KEY': '',
            'CHINGUISOFT_VALIDATION_KEY': '',
            'SMS_TOKEN': token,
            'CHINGUI_SOFT_TOKEN': '',
            'CHINGUISOFT_TOKEN': '',
        }

    def _set_setting(self, key, value):
        self.settings.search([('key', '=', key)]).unlink()
        return self.settings.create({
            'key': key,
            'value': str(value),
            'active': True,
        })

    def _codes(self, result):
        return {issue['code'] for issue in result['issues']}

    def _group_ids(self, xmlids):
        ids = []
        for xmlid in xmlids:
            group = self.env.ref(xmlid, raise_if_not_found=False)
            if group:
                ids.append(group.id)
        return ids

    def _existing_partner(self):
        partner = self.env.user.sudo().partner_id or self.env.company.sudo().partner_id
        self.assertTrue(partner)
        return partner

    def _create_mobile_identity_user(self, login, mobile_phone=False):
        Users = self.env['res.users'].sudo().with_context(no_reset_password=True)
        valid_phone = _acpec_test_mobile_phone(login)
        user = Users.create({
            'name': login,
            'login': valid_phone,
            'mobile_phone': valid_phone,
            'partner_id': self._existing_partner().id,
            'acpec_mobile_only': True,
            'acpec_mobile_state': 'approved',
            'password': Users._acpec_mobile_unusable_password(),
            'group_ids': [(6, 0, self._group_ids([
                'base.group_portal',
                'acpec_mobile_auth.group_mobile_auth_user',
            ]))],
        })

        # Readiness tests intentionally simulate legacy broken data.  After
        # Patch43F2A this can no longer go through ORM; corrupt it directly.
        if mobile_phone is False:
            self.env.cr.execute(
                "UPDATE res_users SET login=%s, acpec_mobile_phone=NULL WHERE id=%s",
                (login, user.id),
            )
        elif login != mobile_phone or not Users._acpec_is_canonical_mobile_phone(mobile_phone):
            self.env.cr.execute(
                "UPDATE res_users SET login=%s, acpec_mobile_phone=%s WHERE id=%s",
                (login, mobile_phone, user.id),
            )
        self.env.invalidate_all()
        return user

    def _check(self, env, include_mobile_identity=False, include_qr_secret=False):
        # Odoo tests run with --test-enable. Patch36A readiness must still be
        # testable for simulated production/dev runtime values.  Most readiness
        # tests target runtime/SMS settings and must not depend on legacy users
        # already present in the developer database; identity-specific tests opt
        # in explicitly. QR-secret-specific tests opt in explicitly too.
        with ExitStack() as stack:
            stack.enter_context(patch.dict(os.environ, env, clear=False))
            stack.enter_context(patch(
                'odoo.addons.acpec_mobile_auth.models.mobile_security_policy.config',
                {'test_enable': False},
            ))
            if not include_mobile_identity:
                stack.enter_context(patch.object(
                    type(self.readiness),
                    '_mobile_identity_issues',
                    lambda _readiness: [],
                ))
            if not include_qr_secret:
                stack.enter_context(patch.object(
                    type(self.readiness),
                    '_qr_numeric_secret_issues',
                    lambda _readiness: [],
                ))
            return self.readiness.check_mobile_security_readiness()

    def test_fueltoken_company_missing_is_reported_as_critical(self):
        Company = self.env['res.company'].sudo()
        Company.search([('acpec_fueltoken_enabled', '=', True)]).write({
            'acpec_fueltoken_enabled': False,
        })

        env = {}
        env.update(self._runtime_env('production'))
        env.update(self._sms_env(validation_key='validation-key', token='sms-token'))
        result = self._check(env)

        self.assertFalse(result['ready'])
        self.assertIn('FUELTOKEN_COMPANY_MISSING', self._codes(result))

    def test_fueltoken_company_not_unique_is_reported_as_critical(self):
        env = {}
        env.update(self._runtime_env('production'))
        env.update(self._sms_env(validation_key='validation-key', token='sms-token'))
        def _fake_fueltoken_company_count(_readiness):
            return 2

        with patch.object(
            type(self.readiness),
            '_fueltoken_company_count',
            _fake_fueltoken_company_count,
        ):
            result = self._check(env)

        self.assertFalse(result['ready'])
        self.assertIn('FUELTOKEN_COMPANY_NOT_UNIQUE', self._codes(result))

    def test_mobile_identity_missing_phone_is_reported_as_critical(self):
        self._create_mobile_identity_user('identity-missing-phone-43f1@example.com')

        env = {}
        env.update(self._runtime_env('production'))
        env.update(self._sms_env(validation_key='validation-key', token='sms-token'))
        result = self._check(env, include_mobile_identity=True)

        self.assertFalse(result['ready'])
        self.assertIn('MOBILE_IDENTITY_MOBILE_PHONE_MISSING', self._codes(result))

    def test_mobile_identity_invalid_phone_is_reported_as_critical(self):
        self._create_mobile_identity_user('32348001', '+222 32 34 80 01')

        env = {}
        env.update(self._runtime_env('production'))
        env.update(self._sms_env(validation_key='validation-key', token='sms-token'))
        result = self._check(env, include_mobile_identity=True)

        self.assertFalse(result['ready'])
        self.assertIn('MOBILE_IDENTITY_MOBILE_PHONE_INVALID', self._codes(result))

    def test_mobile_identity_login_phone_mismatch_is_reported_as_critical(self):
        self._create_mobile_identity_user('32348002', '32348003')

        env = {}
        env.update(self._runtime_env('production'))
        env.update(self._sms_env(validation_key='validation-key', token='sms-token'))
        result = self._check(env, include_mobile_identity=True)

        self.assertFalse(result['ready'])
        self.assertIn('MOBILE_IDENTITY_LOGIN_PHONE_MISMATCH', self._codes(result))

    def test_mobile_identity_duplicate_phone_is_reported_as_critical(self):
        env = {}
        env.update(self._runtime_env('production'))
        env.update(self._sms_env(validation_key='validation-key', token='sms-token'))

        with patch.object(
            type(self.readiness),
            '_mobile_identity_duplicate_phone_rows',
            lambda _readiness: [('32348004', 2)],
        ):
            result = self._check(env, include_mobile_identity=True)

        self.assertFalse(result['ready'])
        self.assertIn('MOBILE_IDENTITY_MOBILE_PHONE_NOT_UNIQUE', self._codes(result))

    def test_dev_gate_allows_zero_antiflood_without_sms_readiness_failure(self):
        self._set_setting('acpec_mobile_auth.otp_request_cooldown_seconds', '0')

        env = {}
        env.update(self._runtime_env('dev', dev_mode='1'))
        env.update(self._sms_env())
        result = self._check(env)

        self.assertFalse(result['production'])
        self.assertEqual(result['runtime_env_label'], 'DEV_LIKE')
        self.assertTrue(result['runtime_dev_relax'])
        self.assertTrue(result['ready'])
        self.assertFalse(result['issues'])

    def test_qr_numeric_secret_missing_for_existing_qr_is_reported_as_critical(self):
        env = {}
        env.update(self._runtime_env('production'))
        env.update(self._sms_env(validation_key='validation-key', token='sms-token'))

        status = {
            'installed': True,
            'ok': False,
            'missing': True,
            'weak': False,
            'hashed_count': 1,
            'model': 'acpec.fueltoken.security.settings',
            'field': 'qr_numeric_secret',
            'min_length': 32,
        }
        with patch.object(
            type(self.readiness),
            '_qr_numeric_secret_status',
            lambda _readiness: status,
        ):
            result = self._check(env, include_qr_secret=True)

        self.assertFalse(result['ready'])
        self.assertIn(
            'QR_NUMERIC_CODE_SECRET_MISSING_FOR_EXISTING_QR',
            self._codes(result),
        )

    def test_qr_numeric_secret_weak_for_existing_qr_is_reported_as_critical(self):
        env = {}
        env.update(self._runtime_env('production'))
        env.update(self._sms_env(validation_key='validation-key', token='sms-token'))

        status = {
            'installed': True,
            'ok': False,
            'missing': False,
            'weak': True,
            'hashed_count': 2,
            'model': 'acpec.fueltoken.security.settings',
            'field': 'qr_numeric_secret',
            'min_length': 32,
        }
        with patch.object(
            type(self.readiness),
            '_qr_numeric_secret_status',
            lambda _readiness: status,
        ):
            result = self._check(env, include_qr_secret=True)

        self.assertFalse(result['ready'])
        self.assertIn(
            'QR_NUMERIC_CODE_SECRET_WEAK_FOR_EXISTING_QR',
            self._codes(result),
        )

    def test_qr_numeric_secret_missing_before_first_qr_is_warning_only(self):
        env = {}
        env.update(self._runtime_env('production'))
        env.update(self._sms_env(validation_key='validation-key', token='sms-token'))

        status = {
            'installed': True,
            'ok': False,
            'missing': True,
            'weak': False,
            'hashed_count': 0,
            'model': 'acpec.fueltoken.security.settings',
            'field': 'qr_numeric_secret',
            'min_length': 32,
        }
        with patch.object(
            type(self.readiness),
            '_qr_numeric_secret_status',
            lambda _readiness: status,
        ):
            result = self._check(env, include_qr_secret=True)

        self.assertTrue(result['ready'])
        self.assertIn(
            'QR_NUMERIC_CODE_SECRET_NOT_INITIALIZED',
            self._codes(result),
        )

    def test_legacy_otp_dev_setting_is_reported_as_critical(self):
        self._set_setting('acpec_mobile_auth.otp_dev_mode', 'True')

        env = {}
        env.update(self._runtime_env('dev', dev_mode='1'))
        env.update(self._sms_env())
        result = self._check(env)

        self.assertFalse(result['ready'])
        self.assertIn('OTP_DEV_MODE_LEGACY_SETTING_ENABLED', self._codes(result))

    def test_production_rejects_configured_zero_antiflood_values_before_safe_fallback(self):
        for key in self.keys[1:]:
            self._set_setting(key, '0')

        env = {}
        env.update(self._runtime_env('production'))
        env.update(self._sms_env(validation_key='validation-key', token='sms-token'))
        result = self._check(env)

        codes = self._codes(result)
        self.assertFalse(result['ready'])
        self.assertIn('OTP_REQUEST_COOLDOWN_ZERO', codes)
        self.assertIn('OTP_IDENTIFIER_PER_MINUTE_ZERO', codes)
        self.assertIn('OTP_IDENTIFIER_PER_DAY_ZERO', codes)
        self.assertIn('OTP_IP_PER_HOUR_ZERO', codes)
        self.assertIn('OTP_REGISTER_IP_PER_DAY_ZERO', codes)

    def test_production_chinguisoft_requires_secret_configuration(self):
        env = {}
        env.update(self._runtime_env('production'))
        env.update(self._sms_env())
        result = self._check(env)

        codes = self._codes(result)
        self.assertIn('SMS_VALIDATION_KEY_MISSING', codes)
        self.assertIn('SMS_TOKEN_MISSING', codes)
        self.assertNotIn('SMS_URL_MISSING', codes)
        self.assertFalse(result['ready'])

    def test_production_sms_env_aliases_are_accepted(self):
        env = self._runtime_env('production')
        env.update(self._sms_env())
        env.update({
            'CHINGUI_SOFT_VALIDATION_KEY': 'validation-key-from-env',
            'CHINGUI_SOFT_TOKEN': 'sms-token-from-env',
        })
        result = self._check(env)

        self.assertTrue(result['production'])
        self.assertTrue(result['ready'])
        self.assertFalse(result['issues'])

    def test_ready_when_production_configuration_is_safe(self):
        self._set_setting('acpec_mobile_auth.otp_request_cooldown_seconds', '60')
        self._set_setting('acpec_mobile_auth.otp_limit_identifier_per_minute', '1')
        self._set_setting('acpec_mobile_auth.otp_limit_identifier_per_day', '10')
        self._set_setting('acpec_mobile_auth.otp_limit_ip_per_hour', '30')
        self._set_setting('acpec_mobile_auth.otp_limit_register_ip_per_day', '100')

        env = {}
        env.update(self._runtime_env('production'))
        env.update(self._sms_env(validation_key='validation-key', token='sms-token'))
        result = self._check(env)

        self.assertTrue(result['production'])
        self.assertTrue(result['ready'])
        self.assertFalse(result['issues'])
