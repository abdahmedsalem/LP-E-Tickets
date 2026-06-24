import hashlib
import os
from types import SimpleNamespace
from unittest.mock import patch

from odoo.exceptions import AccessError, ValidationError
from odoo.tests import TransactionCase, tagged
from odoo.addons.acpec_mobile_auth.controllers.api_public import AcpecMobileAuthApiPublic

MOBILE_SECURITY_SETTING_TEST_KEYS = [
    'acpec_mobile_auth.access_token_minutes',
    'acpec_mobile_auth.refresh_token_days',
    'acpec_mobile_auth.refresh_token_grace_seconds',
    'acpec_mobile_auth.mobile_pin_lock_seconds',
    'acpec_mobile_auth.mobile_pin_max_attempts',
    'acpec_mobile_auth.mobile_pin_hard_block_attempts',
    'acpec_mobile_auth.otp_code_length',
    'acpec_mobile_auth.otp_expiration_minutes',
    'acpec_mobile_auth.otp_max_attempts',
    'acpec_mobile_auth.otp_request_cooldown_seconds',
    'acpec_mobile_auth.otp_limit_identifier_per_minute',
    'acpec_mobile_auth.otp_limit_identifier_per_day',
    'acpec_mobile_auth.otp_limit_ip_per_hour',
    'acpec_mobile_auth.otp_limit_register_ip_per_day',
    'acpec_mobile_auth.otp_dev_mode',
]


from odoo.addons.acpec_mobile_auth_otp.controllers.api_otp import AcpecMobileAuthOtpApi


@tagged('-at_install', 'post_install')
class TestAcpecMobileAuthOtpSms(TransactionCase):

    def setUp(self):
        super().setUp()
        self._env_snapshot = {
            key: os.environ.get(key)
            for key in (
                'ACPEC_ENV',
                'ODOO_ENV',
                'ENV',
                'ACPEC_FUELTOKEN_DEV_MODE',
                'ACPEC_FUELTOKEN_TEST_MODE',
            )
        }
        for key in self._env_snapshot:
            os.environ[key] = ''

        self.env['acpec.mobile.security.setting'].sudo().search([
            ('key', 'in', MOBILE_SECURITY_SETTING_TEST_KEYS),
        ]).unlink()

        # Keep legacy OTP tests independent from historical rows in the dev DB.
        # Dedicated rate-limit tests override these values explicitly.
        self._set_security_setting('acpec_mobile_auth.otp_limit_identifier_per_minute', '0')
        self._set_security_setting('acpec_mobile_auth.otp_limit_identifier_per_day', '0')
        self._set_security_setting('acpec_mobile_auth.otp_limit_ip_per_hour', '0')
        self._set_security_setting('acpec_mobile_auth.otp_limit_register_ip_per_day', '0')
        self._set_security_setting('acpec_mobile_auth.otp_code_length', '6')
        self._set_security_setting('acpec_mobile_auth.otp_dev_mode', '0')

        # Most tests focus on policy/controller behavior, not the external SMS
        # transport. The gateway payload test calls acpec.sms.gateway directly.
        self._send_otp_patcher = patch(
            'odoo.addons.acpec_mobile_auth_otp.models.mobile_auth_otp.AcpecMobileAuthOtp._send_otp_code',
            return_value=True,
        )
        self._send_otp_patcher.start()
        self.addCleanup(self._send_otp_patcher.stop)


    def tearDown(self):
        for key, value in getattr(self, '_env_snapshot', {}).items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        super().tearDown()

    def _set_security_setting(self, key, value, active=True):
        """Patch36A test helper.

        Mobile security settings are read from acpec.mobile.security.setting.
        The legacy otp_dev_mode key no longer opens dev mode; in this test file
        old calls setting otp_dev_mode=True are interpreted as an explicit dev
        runtime gate to preserve the intent of the legacy tests.
        """
        if key == 'acpec_mobile_auth.otp_dev_mode':
            if str(value).strip().casefold() in ('1', 'true', 'yes', 'y', 'on'):
                os.environ['ACPEC_ENV'] = 'dev'
                os.environ['ODOO_ENV'] = ''
                os.environ['ENV'] = ''
                os.environ['ACPEC_FUELTOKEN_DEV_MODE'] = '1'
                os.environ['ACPEC_FUELTOKEN_TEST_MODE'] = ''
            else:
                os.environ['ACPEC_FUELTOKEN_DEV_MODE'] = ''
                os.environ['ACPEC_FUELTOKEN_TEST_MODE'] = ''
            return False

        settings = self.env['acpec.mobile.security.setting'].sudo()
        settings.search([('key', '=', key)]).unlink()
        return settings.create({
            'key': key,
            'value': str(value),
            'active': active,
        })


    def _create_mobile_user(
        self,
        login='otp.sms@example.com',
        mobile_phone='44800028',
        lang='fr_FR',
        active=True,
        mobile_state='approved',
    ):
        partner = self.env['res.partner'].create({'name': 'OTP SMS User'})
        user = self.env['res.users'].sudo().with_context(no_reset_password=True).create({
            'name': 'OTP SMS User',
            'login': login,
            'partner_id': partner.id,
            'company_id': self.env.company.id,
            'company_ids': [(6, 0, [self.env.company.id])],
            'mobile_phone': mobile_phone,
            'lang': lang,
        })
        user.write({
            'active': active,
            'mobile_state': mobile_state,
        })
        return user

    def _assert_otp_code_shape(self, code):
        self.assertTrue(code)
        self.assertTrue(str(code).isdigit())
        self.assertEqual(len(str(code)), 6)


    def test_password_login_is_disabled_and_secret_code_is_not_login_password(self):
        controller = AcpecMobileAuthApiPublic()
        result = controller.password_login(identifier='32520000', secret_code='1234')
        self.assertFalse(result['ok'])
        self.assertEqual(result['error']['code'], 'PASSWORD_LOGIN_DISABLED')

    def test_otp_sms_default_is_six_and_secret_code_is_four(self):
        icp = self.env['ir.config_parameter'].sudo()
        icp.search([('key', '=', 'acpec_mobile_auth.otp_code_length')]).unlink()

        otp_model = self.env['acpec.mobile.auth.otp'].sudo()
        self.assertEqual(otp_model._otp_code_length(), 6)
        self._assert_otp_code_shape(otp_model._new_code())

        controller = AcpecMobileAuthApiPublic()
        controller._validate_secret_code('1234')
        # The helper is normally executed in an HTTP/Odoo request context.
        # Patch the module-level translator for this direct unit call so the
        # assertion checks the business rule (secret_code = 4 digits) instead
        # of failing on request-bound translation lookup.
        with patch('odoo.addons.acpec_mobile_auth.controllers.api_common._', lambda message: message):
            with self.assertRaises(ValidationError):
                controller._validate_secret_code('123456')

    def test_sms_gateway_posts_validation_sms_to_chinguisoft(self):
        # Keep the provider payload test focused on the gateway itself.
        # OTP-flow tests below verify challenge creation independently; this
        # avoids coupling them to Odoo's model dispatch/proxying internals.
        icp = self.env['ir.config_parameter'].sudo()
        icp.set_param('SMS_PROVIDER', 'chinguisoft')
        icp.set_param('SMS_VALIDATION_KEY', 'test-validation-key')
        icp.set_param('SMS_TOKEN', 'test-validation-token')
        icp.set_param('SMS_URL', 'https://chinguisoft.com/api/sms/validation')
        icp.set_param('SMS_DEFAULT_LANG', 'fr')

        class FakeResponse:
            status_code = 200
            text = '{"status": "ok", "message_id": "sms-test-1", "balance": 99}'

            def json(self):
                return {'status': 'ok', 'message_id': 'sms-test-1', 'balance': 99}

        with patch('odoo.addons.acpec_mobile_auth_otp.models.sms_gateway.requests.post', return_value=FakeResponse()) as mocked_post:
            result = self.env['acpec.sms.gateway'].sudo().send_validation_sms(
                '32524658',
                code='123456',
                lang='fr',
            )

        self.assertEqual(result['status'], 'ok')
        self.assertEqual(result['message_id'], 'sms-test-1')
        mocked_post.assert_called_once()
        args, kwargs = mocked_post.call_args
        self.assertEqual(args[0], 'https://chinguisoft.com/api/sms/validation/test-validation-key')
        self.assertEqual(kwargs['headers']['Validation-token'], 'test-validation-token')
        self.assertEqual(kwargs['headers']['Content-Type'], 'application/json')
        self.assertEqual(kwargs['json']['phone'], '32524658')
        self.assertEqual(kwargs['json']['lang'], 'fr')
        self.assertEqual(kwargs['json']['code'], '123456')
        self.assertEqual(kwargs['timeout'], 15)

    def test_request_otp_creates_configured_provider_challenge(self):
        icp = self.env['ir.config_parameter'].sudo()
        icp.set_param('SMS_PROVIDER', 'chinguisoft')
        icp.set_param('SMS_VALIDATION_KEY', 'test-validation-key')
        icp.set_param('SMS_TOKEN', 'test-validation-token')
        icp.set_param('SMS_URL', 'https://chinguisoft.com/api/sms/validation')
        icp.set_param('SMS_DEFAULT_LANG', 'fr')
        self._set_security_setting('acpec_mobile_auth.otp_dev_mode', '0')

        with patch('odoo.addons.acpec_mobile_auth_otp.models.mobile_auth_otp.AcpecMobileAuthOtp._send_otp_code', return_value=True):
            challenge, code = self.env['acpec.mobile.auth.otp'].sudo().request_otp('32524658', purpose='register')

        self.assertTrue(challenge)
        self.assertEqual(challenge.state, 'pending')
        self.assertEqual(challenge.mobile, '32524658')
        self._assert_otp_code_shape(code)
        self.assertFalse(self.env['acpec.mobile.auth.account.request'].sudo().search([
            ('signup_identifier', '=', '32524658'),
            ('state', '=', 'pending'),
        ], limit=1))

    def test_otp_dev_mode_policy_requires_runtime_gate(self):
        policy = self.env['acpec.mobile.security.policy'].sudo()

        self._set_security_setting('acpec_mobile_auth.otp_dev_mode', 'True')
        self.assertTrue(policy.otp_dev_mode_enabled())

        os.environ['ACPEC_ENV'] = 'prod'
        os.environ['ACPEC_FUELTOKEN_DEV_MODE'] = '1'
        self.assertFalse(policy.otp_dev_mode_enabled())

    def _public_controller_request_context(self, remote_addr='127.0.0.1'):
        fake_request = SimpleNamespace(
            env=self.env,
            cr=self.env.cr,
            httprequest=SimpleNamespace(
                headers={},
                remote_addr=remote_addr,
                access_route=[remote_addr],
                environ={'REMOTE_ADDR': remote_addr},
            ),
        )

        def fake_translate(message, *args, **kwargs):
            return message

        return patch.multiple(
            'odoo.addons.acpec_mobile_auth.controllers.api_common',
            request=fake_request,
            _=fake_translate,
        ), patch.multiple(
            'odoo.addons.acpec_mobile_auth.controllers.api_public',
            request=fake_request,
            _=fake_translate,
        ), patch.multiple(
            'odoo.addons.acpec_mobile_auth_otp.controllers.api_otp',
            request=fake_request,
            _=fake_translate,
        )

    def _run_public_controller_call(self, callback):
        common_patch, public_patch, otp_patch = self._public_controller_request_context()
        with common_patch, public_patch, otp_patch:
            return callback()

    def _assert_public_error_is_not_enumerating(self, result):
        self.assertFalse(result['ok'])
        serialized = str(result).lower()
        forbidden_terms = [
            'account_exists',
            'otp_not_found',
            'already exists',
            'introuvable',
            'not found',
            'déjà existant',
            'existe déjà',
            'compte mobile introuvable',
        ]
        for term in forbidden_terms:
            self.assertNotIn(term, serialized)

    def _assert_latest_signup_denial_audit(self, debug_term=False, company=False):
        audit = self.env['acpec.mobile.security.audit.log'].sudo().search([
            ('event_type', '=', 'mobile_signup_not_allowed'),
            ('code', '=', 'SIGNUP_NOT_ALLOWED'),
        ], order='id desc', limit=1)
        self.assertTrue(audit)
        self.assertFalse(audit.success)
        self.assertTrue(audit.blocked)
        self.assertIn('Impossible de finaliser', audit.public_message or '')
        if debug_term:
            self.assertIn(debug_term, audit.debug_reason or '')
        if company:
            self.assertEqual(audit.company_id, company)

    def test_signup_existing_account_uses_generic_public_error(self):
        self.env.company.write({'acpec_mobile_auth_enabled': True})
        self._create_mobile_user(
            login='46009101',
            mobile_phone='46009101',
        )
        controller = AcpecMobileAuthApiPublic()

        with patch('odoo.addons.acpec_mobile_auth.models.mobile_security_policy.os.getenv', return_value=''):
            with patch('odoo.addons.acpec_mobile_auth.models.mobile_security_policy.config', {'test_enable': False}):
                result = self._run_public_controller_call(lambda: controller.signup(
                    name='Existing Signup',
                    signup_identifier='46009101',
                    secret_code='1234',
                    company_id=self.env.company.id,
                ))

        self._assert_public_error_is_not_enumerating(result)
        self.assertEqual(result['error']['code'], 'SIGNUP_NOT_ALLOWED')
        self.assertNotIn('debug_reason', result['error'])
        self._assert_latest_signup_denial_audit('A mobile account already exists', company=self.env.company)

    def test_signup_disabled_company_audits_technical_reason_without_public_leak(self):
        self.env.company.write({'acpec_mobile_auth_enabled': False})
        controller = AcpecMobileAuthApiPublic()

        with patch('odoo.addons.acpec_mobile_auth.models.mobile_security_policy.os.getenv', return_value=''):
            with patch('odoo.addons.acpec_mobile_auth.models.mobile_security_policy.config', {'test_enable': False}):
                result = self._run_public_controller_call(lambda: controller.signup(
                    name='Disabled Company Signup',
                    signup_identifier='46009104',
                    secret_code='1234',
                    company_id=self.env.company.id,
                ))

        self._assert_public_error_is_not_enumerating(result)
        self.assertEqual(result['error']['code'], 'SIGNUP_NOT_ALLOWED')
        self.assertNotIn('debug_reason', result['error'])
        self._assert_latest_signup_denial_audit(
            'This company does not accept mobile application registration',
            company=self.env.company,
        )

    def test_request_otp_register_existing_account_uses_generic_public_error(self):
        self._create_mobile_user(
            login='46009102',
            mobile_phone='46009102',
        )
        controller = AcpecMobileAuthOtpApi()

        with patch('odoo.addons.acpec_mobile_auth.models.mobile_security_policy.os.getenv', return_value=''):
            with patch('odoo.addons.acpec_mobile_auth.models.mobile_security_policy.config', {'test_enable': False}):
                result = self._run_public_controller_call(lambda: controller.request_otp(
                    identifier='46009102',
                    purpose='register',
                ))

        self._assert_public_error_is_not_enumerating(result)
        self.assertEqual(result['error']['code'], 'SIGNUP_NOT_ALLOWED')
        self.assertNotIn('debug_reason', result['error'])
        self._assert_latest_signup_denial_audit('A mobile account already exists')

    def test_request_otp_login_unknown_identifier_returns_account_not_found(self):
        controller = AcpecMobileAuthOtpApi()

        with patch('odoo.addons.acpec_mobile_auth.models.mobile_security_policy.os.getenv', return_value=''):
            with patch('odoo.addons.acpec_mobile_auth.models.mobile_security_policy.config', {'test_enable': False}):
                result = self._run_public_controller_call(lambda: controller.request_otp(
                    identifier='46999999',
                    purpose='login',
                ))

        self.assertFalse(result['ok'])
        self.assertEqual(result['error']['code'], 'ACCOUNT_NOT_FOUND')
        self.assertEqual(result['error']['message'], 'Aucun compte mobile n’est associé à ce numéro. Veuillez vous inscrire pour créer un compte.')
        self.assertNotIn('debug_reason', result['error'])

    def test_request_otp_reset_unknown_identifier_returns_account_not_found(self):
        controller = AcpecMobileAuthOtpApi()

        with patch('odoo.addons.acpec_mobile_auth.models.mobile_security_policy.os.getenv', return_value=''):
            with patch('odoo.addons.acpec_mobile_auth.models.mobile_security_policy.config', {'test_enable': False}):
                result = self._run_public_controller_call(lambda: controller.request_otp(
                    identifier='46999998',
                    purpose='reset',
                ))

        self.assertFalse(result['ok'])
        self.assertEqual(result['error']['code'], 'ACCOUNT_NOT_FOUND')
        self.assertEqual(result['error']['message'], 'Aucun compte mobile n’est associé à ce numéro. Veuillez vous inscrire pour créer un compte.')
        self.assertNotIn('debug_reason', result['error'])

    def test_verify_otp_unknown_challenge_uses_generic_public_error(self):
        controller = AcpecMobileAuthOtpApi()

        with patch('odoo.addons.acpec_mobile_auth.models.mobile_security_policy.os.getenv', return_value=''):
            with patch('odoo.addons.acpec_mobile_auth.models.mobile_security_policy.config', {'test_enable': False}):
                result = self._run_public_controller_call(lambda: controller.verify_otp(
                    challenge_id=999999999,
                    code='123456',
                ))

        self._assert_public_error_is_not_enumerating(result)
        self.assertEqual(result['error']['code'], 'OTP_INVALID_OR_EXPIRED')
        self.assertNotIn('debug_reason', result['error'])

    def test_verify_otp_register_duplicate_account_uses_generic_public_error(self):
        self.env.company.write({'acpec_mobile_auth_enabled': True})
        controller = AcpecMobileAuthOtpApi()
        otp_model = self.env['acpec.mobile.auth.otp'].sudo()

        challenge, code = otp_model.request_otp(
            '46009103',
            purpose='register',
            request_ip='127.0.0.1',
        )

        self._create_mobile_user(
            login='46009103',
            mobile_phone='46009103',
        )

        with patch('odoo.addons.acpec_mobile_auth.models.mobile_security_policy.os.getenv', return_value=''):
            with patch('odoo.addons.acpec_mobile_auth.models.mobile_security_policy.config', {'test_enable': False}):
                result = self._run_public_controller_call(lambda: controller.verify_otp(
                    challenge_id=challenge.id,
                    code=code,
                    name='Duplicate Register',
                    secret_code='1234',
                    company_id=self.env.company.id,
                    device_uid='ft-android-test-duplicate-register-46009103',
                    device_name='Flutter Android',
                    platform='android',
                    app_version='test',
                ))

        self._assert_public_error_is_not_enumerating(result)
        self.assertEqual(result['error']['code'], 'SIGNUP_NOT_ALLOWED')
        self.assertNotIn('debug_reason', result['error'])
        self._assert_latest_signup_denial_audit('A mobile account already exists', company=self.env.company)

    def test_request_otp_login_unknown_identifier_debug_reason_is_runtime_gated(self):

        controller = AcpecMobileAuthOtpApi()

        os.environ['ACPEC_ENV'] = 'prod'
        os.environ['ODOO_ENV'] = ''
        os.environ['ENV'] = ''
        os.environ['ACPEC_FUELTOKEN_DEV_MODE'] = ''
        os.environ['ACPEC_FUELTOKEN_TEST_MODE'] = ''

        result = self._run_public_controller_call(lambda: controller.request_otp(
            identifier='unknown-login-runtime-gated@example.com',
            purpose='login',
        ))
        self.assertFalse(result['ok'])
        self.assertEqual(result['error']['code'], 'ACCOUNT_NOT_FOUND')
        self.assertNotIn('debug_reason', result['error'])

        os.environ['ACPEC_ENV'] = 'dev'
        os.environ['ACPEC_FUELTOKEN_DEV_MODE'] = '1'

        result = self._run_public_controller_call(lambda: controller.request_otp(
            identifier='unknown-login-runtime-gated@example.com',
            purpose='login',
        ))
        self.assertFalse(result['ok'])
        self.assertEqual(result['error']['code'], 'ACCOUNT_NOT_FOUND')
        self.assertEqual(result['error'].get('debug_reason'), 'user_not_found')

    def test_verify_otp_unknown_challenge_debug_reason_is_runtime_gated(self):

        controller = AcpecMobileAuthOtpApi()

        os.environ['ACPEC_ENV'] = 'prod'
        os.environ['ODOO_ENV'] = ''
        os.environ['ENV'] = ''
        os.environ['ACPEC_FUELTOKEN_DEV_MODE'] = ''
        os.environ['ACPEC_FUELTOKEN_TEST_MODE'] = ''

        result = self._run_public_controller_call(lambda: controller.verify_otp(
            challenge_id=99999999,
            code='000000',
        ))
        self.assertFalse(result['ok'])
        self.assertNotIn('debug_reason', result['error'])

        os.environ['ACPEC_ENV'] = 'dev'
        os.environ['ACPEC_FUELTOKEN_DEV_MODE'] = '1'

        result = self._run_public_controller_call(lambda: controller.verify_otp(
            challenge_id=99999999,
            code='000000',
        ))
        self.assertFalse(result['ok'])
        self.assertEqual(result['error'].get('debug_reason'), 'otp_not_found')

    def test_otp_antiflood_zero_values_require_runtime_gate(self):

        policy = self.env['acpec.mobile.security.policy'].sudo()
        self._set_security_setting('acpec_mobile_auth.otp_request_cooldown_seconds', '0')
        self._set_security_setting('acpec_mobile_auth.otp_limit_identifier_per_minute', '0')
        self._set_security_setting('acpec_mobile_auth.otp_limit_identifier_per_day', '0')
        self._set_security_setting('acpec_mobile_auth.otp_limit_ip_per_hour', '0')
        self._set_security_setting('acpec_mobile_auth.otp_limit_register_ip_per_day', '0')

        os.environ['ACPEC_ENV'] = 'prod'
        os.environ['ODOO_ENV'] = ''
        os.environ['ENV'] = ''
        os.environ['ACPEC_FUELTOKEN_DEV_MODE'] = ''
        os.environ['ACPEC_FUELTOKEN_TEST_MODE'] = ''

        self.assertEqual(policy.otp_request_cooldown_seconds(), 60)
        self.assertEqual(policy.otp_limit_identifier_per_minute(), 1)
        self.assertEqual(policy.otp_limit_identifier_per_day(), 10)
        self.assertEqual(policy.otp_limit_ip_per_hour(), 30)
        self.assertEqual(policy.otp_limit_register_ip_per_day(), 100)

        os.environ['ACPEC_ENV'] = 'dev'
        os.environ['ACPEC_FUELTOKEN_DEV_MODE'] = '1'

        self.assertEqual(policy.otp_request_cooldown_seconds(), 0)
        self.assertEqual(policy.otp_limit_identifier_per_minute(), 0)
        self.assertEqual(policy.otp_limit_identifier_per_day(), 0)
        self.assertEqual(policy.otp_limit_ip_per_hour(), 0)
        self.assertEqual(policy.otp_limit_register_ip_per_day(), 0)

    def test_request_otp_route_hides_dev_code_without_runtime_gate(self):
        icp = self.env['ir.config_parameter'].sudo()
        self._set_security_setting('acpec_mobile_auth.otp_dev_mode', 'True')
        icp.set_param('SMS_PROVIDER', '')
        icp.set_param('SMS_VALIDATION_KEY', '')
        icp.set_param('SMS_TOKEN', '')
        icp.set_param('SMS_URL', '')
        self._set_security_setting('acpec_mobile_auth.otp_request_cooldown_seconds', '0')

        controller = AcpecMobileAuthOtpApi()
        controller._require_keys = lambda params, keys: None
        controller._get_clean_str = lambda params, key: str(params.get(key) or '').strip()
        dummy_httprequest = SimpleNamespace(
            remote_addr='127.0.0.1',
            headers={'User-Agent': 'pytest'},
        )
        dummy_request = SimpleNamespace(env=self.env, cr=self.env.cr, httprequest=dummy_httprequest)

        with patch('odoo.addons.acpec_mobile_auth.controllers.api_common.request', dummy_request), \
                patch('odoo.addons.acpec_mobile_auth_otp.controllers.api_otp.request', dummy_request), \
                patch('odoo.addons.acpec_mobile_auth_otp.models.mobile_auth_otp.AcpecMobileAuthOtp._send_otp_code', return_value=True), \
                patch('odoo.addons.acpec_mobile_auth.models.mobile_security_policy.os.getenv', return_value=''), \
                patch('odoo.addons.acpec_mobile_auth.models.mobile_security_policy.config', {'test_enable': False}):
            result = controller.request_otp(
                identifier='32526001',
                purpose='register',
            )

        self.assertTrue(result['ok'])
        data = result['data']
        self.assertEqual(data['delivery'], 'configured_provider')
        self.assertEqual(data['otp_delivery'], 'configured_provider')
        self.assertNotIn('dev_otp_code', data)
        self.assertNotIn('otp_dev_code', data)

    def test_request_otp_keeps_dev_mode_without_sms_config(self):
        icp = self.env['ir.config_parameter'].sudo()
        self._set_security_setting('acpec_mobile_auth.otp_dev_mode', 'True')
        icp.set_param('SMS_PROVIDER', '')
        icp.set_param('SMS_VALIDATION_KEY', '')
        icp.set_param('SMS_TOKEN', '')
        icp.set_param('SMS_URL', 'https://chinguisoft.com/api/sms/validation')

        with patch('odoo.addons.acpec_mobile_auth_otp.models.sms_gateway.requests.post') as mocked_post:
            challenge, code = self.env['acpec.mobile.auth.otp'].sudo().request_otp('32524657', purpose='register')

        self.assertTrue(challenge)
        self.assertEqual(challenge.state, 'pending')
        self._assert_otp_code_shape(code)
        mocked_post.assert_not_called()

    def test_request_otp_cancels_previous_pending_challenge_for_identifier(self):
        icp = self.env['ir.config_parameter'].sudo()
        self._set_security_setting('acpec_mobile_auth.otp_dev_mode', 'True')
        self._set_security_setting('acpec_mobile_auth.otp_request_cooldown_seconds', '0')
        self._set_security_setting('acpec_mobile_auth.otp_limit_identifier_per_minute', '0')
        icp.set_param('SMS_PROVIDER', '')
        icp.set_param('SMS_VALIDATION_KEY', '')
        icp.set_param('SMS_TOKEN', '')
        icp.set_param('SMS_URL', '')

        with patch('odoo.addons.acpec_mobile_auth_otp.models.sms_gateway.requests.post'):
            challenge, code = self.env['acpec.mobile.auth.otp'].sudo().request_otp(
                '32524656',
                purpose='register',
            )

        self.assertTrue(challenge)
        self.assertEqual(challenge.state, 'pending')
        self._assert_otp_code_shape(code)

        challenge2, code2 = self.env['acpec.mobile.auth.otp'].sudo().request_otp(
            '32524656',
            purpose='register',
        )

        self.assertTrue(challenge2)
        self.assertNotEqual(challenge2.id, challenge.id)
        self.assertEqual(challenge.state, 'cancelled')
        self.assertEqual(challenge2.state, 'pending')
        self._assert_otp_code_shape(code2)

    def test_hash_otp_uses_sha256(self):
        salt = 'test-salt'
        code = '123456'
        expected = hashlib.scrypt(
            code.encode('utf-8'),
            salt=salt.encode('utf-8'),
            n=2 ** 14,
            r=8,
            p=1,
            dklen=32,
        ).hex()

        with patch(
            'odoo.addons.acpec_mobile_auth_otp.models.mobile_auth_otp.hashlib.scrypt',
            wraps=hashlib.scrypt,
        ):
            actual = self.env['acpec.mobile.auth.otp']._hash_otp(code, salt)

        self.assertEqual(actual, expected)

    def test_register_otp_creates_account_only_after_verification(self):
        self.env.company.write({'acpec_mobile_auth_enabled': True})
        self._set_security_setting('acpec_mobile_auth.otp_dev_mode', 'True')

        otp_controller = AcpecMobileAuthOtpApi()
        otp_controller._require_keys = lambda params, keys: None
        otp_controller._get_clean_str = lambda params, key: str(params.get(key) or '').strip()
        otp_controller._get_optional_int = lambda params, key, default=False: int(params.get(key) or default)
        otp_controller._get_company = lambda company_id=False: self.env.company
        dummy_httprequest = SimpleNamespace(
            remote_addr='127.0.0.1',
            headers={'User-Agent': 'pytest'},
        )
        dummy_request = SimpleNamespace(env=self.env, cr=self.env.cr, httprequest=dummy_httprequest)

        with patch('odoo.addons.acpec_mobile_auth.controllers.api_common.request', dummy_request), \
                patch('odoo.addons.acpec_mobile_auth_otp.controllers.api_otp.request', dummy_request):
            request_result = otp_controller.request_otp(
                identifier='32524655',
                purpose='register',
            )

        self.assertTrue(request_result['ok'])
        request_data = request_result['data']
        self.assertTrue(request_data['otp_challenge_id'])
        self.assertEqual(request_data['otp_delivery'], 'dev_fixed_otp')
        self.assertFalse(self.env['acpec.mobile.auth.account.request'].sudo().search([
            ('signup_identifier', '=', '32524655'),
        ], limit=1))

        with patch('odoo.addons.acpec_mobile_auth.controllers.api_common.request', dummy_request), \
                patch('odoo.addons.acpec_mobile_auth_otp.controllers.api_otp.request', dummy_request):
            no_device_result = otp_controller.verify_otp(
                challenge_id=request_data['otp_challenge_id'],
                identifier='32524655',
                code='000000',
                name='Client OTP',
                secret_code='1234',
                company_id=self.env.company.id,
            )

        self.assertFalse(no_device_result['ok'])
        self.assertEqual(no_device_result['error']['code'], 'SIGNUP_NOT_ALLOWED')
        self.assertEqual(
            no_device_result['error']['message'],
            'Impossible de finaliser l’inscription avec ces informations.',
        )
        self._assert_latest_signup_denial_audit(
            'register_otp_missing_or_unstable_device_uid_before_otp_consumption',
            company=self.env.company,
        )
        self.assertFalse(self.env['res.users'].sudo().search([('login', '=', '32524655')], limit=1))
        self.assertFalse(self.env['acpec.mobile.auth.account.request'].sudo().search([
            ('signup_identifier', '=', '32524655'),
        ], limit=1))

        device_uid = 'ft-android-test-register-32524655'
        with patch('odoo.addons.acpec_mobile_auth.controllers.api_common.request', dummy_request), \
                patch('odoo.addons.acpec_mobile_auth_otp.controllers.api_otp.request', dummy_request):
            verify_result = otp_controller.verify_otp(
                challenge_id=request_data['otp_challenge_id'],
                identifier='32524655',
                code='000000',
                name='Client OTP',
                secret_code='1234',
                company_id=self.env.company.id,
                device_uid=device_uid,
                device_name='Flutter Android',
                platform='android',
                app_version='test',
            )

        self.assertTrue(verify_result['ok'])
        session_data = verify_result['data']
        self.assertTrue(session_data['access_token'])
        self.assertTrue(session_data['refresh_token'])
        self.assertTrue(session_data['session_ref'])
        self.assertTrue(session_data['pending_approval'])
        self.assertTrue(session_data['account_request_id'])
        self.assertEqual(session_data['device_uid'], device_uid)
        self.assertEqual(session_data['device_trust_state'], 'pending_trust')

        user = self.env['res.users'].sudo().search([('login', '=', '32524655')], limit=1)
        self.assertTrue(user)
        self.assertTrue(user.active)
        self.assertEqual(user.login, '32524655')
        self.assertEqual(user.mobile_phone, '32524655')
        self.assertEqual(user.mobile_state, 'self_registered')
        self.assertTrue(user.mobile_pin_set)
        self.assertFalse(user.mobile_pin_required)
        self.assertTrue(user.mobile_pin_hash)
        self.assertTrue(user.mobile_pin_salt)
        user.check_mobile_pin('1234')

        account_request = self.env['acpec.mobile.auth.account.request'].sudo().search([
            ('user_id', '=', user.id),
        ], order='id desc', limit=1)
        self.assertTrue(account_request)
        self.assertEqual(account_request.state, 'approved')
        self.assertTrue(account_request.reviewed_at)

        enrollment_session = self.env['acpec.mobile.session'].sudo().search([
            ('name', '=', session_data['session_ref']),
        ], limit=1)
        self.assertTrue(enrollment_session)
        self.assertEqual(enrollment_session.state, 'active')
        self.assertEqual(enrollment_session.device_uid, device_uid)
        self.assertEqual(enrollment_session.device_trust_state, 'pending_trust')
        self.assertTrue(enrollment_session.is_device_approval_candidate)


    def test_register_otp_validates_payload_before_verification(self):
        self.env.company.write({'acpec_mobile_auth_enabled': True})
        self._set_security_setting('acpec_mobile_auth.otp_dev_mode', 'True')

        otp_controller = AcpecMobileAuthOtpApi()
        otp_controller._require_keys = lambda params, keys: None
        otp_controller._get_clean_str = lambda params, key: str(params.get(key) or '').strip()
        otp_controller._get_optional_int = lambda params, key, default=False: int(params.get(key) or default)
        otp_controller._get_company = lambda company_id=False: self.env.company
        dummy_httprequest = SimpleNamespace(
            remote_addr='127.0.0.1',
            headers={'User-Agent': 'pytest'},
        )
        dummy_request = SimpleNamespace(env=self.env, cr=self.env.cr, httprequest=dummy_httprequest)

        cases = [
            ('32524656', {'name': ''}, 'NAME_REQUIRED'),
            ('32524657', {'secret_code': ''}, 'SECRET_CODE_REQUIRED'),
            ('32524658', {'secret_code': '12ab'}, 'SECRET_CODE_INVALID'),
        ]

        for identifier, overrides, expected_code in cases:
            with patch('odoo.addons.acpec_mobile_auth.controllers.api_common.request', dummy_request), \
                    patch('odoo.addons.acpec_mobile_auth_otp.controllers.api_otp.request', dummy_request):
                request_result = otp_controller.request_otp(
                    identifier=identifier,
                    purpose='register',
                )

            self.assertTrue(request_result['ok'])
            request_data = request_result['data']
            device_uid = 'ft-android-test-register-preverify-%s' % identifier

            payload = {
                'challenge_id': request_data['otp_challenge_id'],
                'identifier': identifier,
                'code': '000000',
                'name': 'Client OTP',
                'secret_code': '1234',
                'company_id': self.env.company.id,
                'device_uid': device_uid,
                'device_name': 'Flutter Android',
                'platform': 'android',
                'app_version': 'test',
            }
            payload.update(overrides)

            with patch('odoo.addons.acpec_mobile_auth.controllers.api_common.request', dummy_request), \
                    patch('odoo.addons.acpec_mobile_auth_otp.controllers.api_otp.request', dummy_request):
                invalid_result = otp_controller.verify_otp(**payload)

            self.assertFalse(invalid_result['ok'])
            if expected_code:
                self.assertEqual(invalid_result['error']['code'], expected_code)
            self.assertFalse(self.env['res.users'].sudo().search([('login', '=', identifier)], limit=1))
            self.assertFalse(self.env['acpec.mobile.auth.account.request'].sudo().search([
                ('signup_identifier', '=', identifier),
            ], limit=1))

            payload.update({
                'name': 'Client OTP',
                'secret_code': '1234',
            })
            with patch('odoo.addons.acpec_mobile_auth.controllers.api_common.request', dummy_request), \
                    patch('odoo.addons.acpec_mobile_auth_otp.controllers.api_otp.request', dummy_request):
                verify_result = otp_controller.verify_otp(**payload)

            self.assertTrue(verify_result['ok'])
            user = self.env['res.users'].sudo().search([('login', '=', identifier)], limit=1)
            self.assertTrue(user)
            self.assertEqual(user.mobile_state, 'self_registered')
            self.assertEqual(verify_result['data']['device_uid'], device_uid)

            account_request = self.env['acpec.mobile.auth.account.request'].sudo().search([
                ('user_id', '=', user.id),
            ], order='id desc', limit=1)
            self.assertTrue(account_request)
            self.assertEqual(account_request.name_display, 'Client OTP')
            self.assertNotEqual(account_request.name, 'Client OTP')


    def test_signup_route_returns_register_otp_payload_for_phone(self):
        self.env.company.write({'acpec_mobile_auth_enabled': True})
        icp = self.env['ir.config_parameter'].sudo()
        icp.set_param('SMS_PROVIDER', 'chinguisoft')
        icp.set_param('SMS_VALIDATION_KEY', 'test-validation-key')
        icp.set_param('SMS_TOKEN', 'test-validation-token')
        icp.set_param('SMS_URL', 'https://chinguisoft.com/api/sms/validation')
        icp.set_param('SMS_DEFAULT_LANG', 'fr')
        self._set_security_setting('acpec_mobile_auth.otp_dev_mode', '0')

        class FakeResponse:
            status_code = 200
            text = '{"status": "ok", "message_id": "sms-test-1"}'

            def json(self):
                return {'status': 'ok', 'message_id': 'sms-test-1'}

        controller = AcpecMobileAuthApiPublic()
        controller._require_keys = lambda params, keys: None
        controller._get_clean_str = lambda params, key: str(params.get(key) or '').strip()
        controller._get_optional_int = lambda params, key, default=False: int(params.get(key) or default)
        controller._get_company = lambda company_id=False: self.env.company
        dummy_httprequest = SimpleNamespace(
            remote_addr='127.0.0.1',
            headers={'User-Agent': 'pytest'},
        )
        dummy_request = SimpleNamespace(env=self.env, cr=self.env.cr, httprequest=dummy_httprequest)

        with patch('odoo.addons.acpec_mobile_auth.controllers.api_public.request', dummy_request), \
                patch('odoo.addons.acpec_mobile_auth.controllers.api_common.request', dummy_request), \
                patch('odoo.addons.acpec_mobile_auth_otp.models.mobile_auth_otp.AcpecMobileAuthOtp._send_otp_code', return_value=True):
            result = controller.signup(
                name='Client OTP',
                signup_identifier='32524758',
                secret_code='1234',
                company_id=self.env.company.id,
                email='client@example.com',
            )

        self.assertTrue(result['ok'])
        data = result['data']
        self.assertEqual(data['signup_identifier_type'], 'phone')
        self.assertEqual(data['signup_identifier'], '32524758')
        self.assertTrue(data['otp_challenge_id'])
        self.assertEqual(data['otp_delivery'], 'configured_provider')

    def test_signup_then_verify_register_otp_activates_user(self):
        self.env.company.write({'acpec_mobile_auth_enabled': True})
        self._set_security_setting('acpec_mobile_auth.otp_dev_mode', 'True')

        controller = AcpecMobileAuthApiPublic()
        otp_controller = AcpecMobileAuthOtpApi()
        controller._require_keys = lambda params, keys: None
        controller._get_clean_str = lambda params, key: str(params.get(key) or '').strip()
        controller._get_optional_int = lambda params, key, default=False: int(params.get(key) or default)
        controller._get_company = lambda company_id=False: self.env.company
        dummy_httprequest = SimpleNamespace(
            remote_addr='127.0.0.1',
            headers={'User-Agent': 'pytest'},
        )
        dummy_request = SimpleNamespace(env=self.env, cr=self.env.cr, httprequest=dummy_httprequest)

        with patch('odoo.addons.acpec_mobile_auth.controllers.api_public.request', dummy_request), \
                patch('odoo.addons.acpec_mobile_auth.controllers.api_common.request', dummy_request), \
                patch('odoo.addons.acpec_mobile_auth_otp.controllers.api_otp.request', dummy_request):
            signup_result = controller.signup(
                name='Client OTP',
                signup_identifier='32524657',
                secret_code='1234',
                company_id=self.env.company.id,
                email='client2@example.com',
            )

        signup_data = signup_result['data']
        challenge_id = signup_data['otp_challenge_id']
        otp_code = '000000'
        device_uid = 'ft-android-test-register-32524657'

        with patch('odoo.addons.acpec_mobile_auth.controllers.api_common.request', dummy_request), \
                patch('odoo.addons.acpec_mobile_auth_otp.controllers.api_otp.request', dummy_request):
            verify_result = otp_controller.verify_otp(
                challenge_id=challenge_id,
                identifier='32524657',
                code=otp_code,
                name='Client OTP',
                secret_code='1234',
                company_id=self.env.company.id,
                email='client2@example.com',
                device_uid=device_uid,
                device_name='Flutter Android',
                platform='android',
                app_version='test',
            )

        self.assertTrue(verify_result['ok'])
        session_data = verify_result['data']
        self.assertTrue(session_data['access_token'])
        self.assertTrue(session_data['refresh_token'])
        self.assertTrue(session_data['session_ref'])
        self.assertTrue(session_data['pending_approval'])
        self.assertEqual(session_data['device_uid'], device_uid)
        self.assertEqual(session_data['device_trust_state'], 'pending_trust')

        user = self.env['res.users'].sudo().search([('login', '=', '32524657')], limit=1)
        self.assertTrue(user.active)
        self.assertEqual(user.login, '32524657')
        self.assertEqual(user.mobile_phone, '32524657')
        self.assertEqual(user.mobile_state, 'self_registered')
        self.assertTrue(user.mobile_pin_set_at)
        self.assertTrue(user.mobile_pin_set)
        self.assertFalse(user.mobile_pin_required)
        self.assertTrue(session_data['mobile_pin_set'])
        self.assertFalse(session_data['mobile_pin_required'])
        user.check_mobile_pin('1234')
        with self.assertRaises(AccessError):
            user.check_mobile_pin('9999')

        account_request = self.env['acpec.mobile.auth.account.request'].sudo().search([
            ('user_id', '=', user.id),
        ], order='id desc', limit=1)
        self.assertTrue(account_request)
        self.assertEqual(account_request.state, 'approved')

        session = self.env['acpec.mobile.session'].sudo().search([
            ('name', '=', session_data['session_ref']),
        ], limit=1)
        self.assertTrue(session)
        self.assertEqual(session.device_uid, device_uid)
        self.assertEqual(session.device_trust_state, 'pending_trust')
        self.assertTrue(session.is_device_approval_candidate)

    def test_signup_then_verify_register_otp_e2e_without_sms_provider(self):
        self.env.company.write({'acpec_mobile_auth_enabled': True})
        self._set_security_setting('acpec_mobile_auth.otp_dev_mode', 'True')

        controller = AcpecMobileAuthApiPublic()
        otp_controller = AcpecMobileAuthOtpApi()
        controller._require_keys = lambda params, keys: None
        controller._get_clean_str = lambda params, key: str(params.get(key) or '').strip()
        controller._get_optional_int = lambda params, key, default=False: int(params.get(key) or default)
        controller._get_company = lambda company_id=False: self.env.company
        dummy_httprequest = SimpleNamespace(
            remote_addr='127.0.0.1',
            headers={'User-Agent': 'pytest'},
        )
        dummy_request = SimpleNamespace(env=self.env, cr=self.env.cr, httprequest=dummy_httprequest)

        with patch('odoo.addons.acpec_mobile_auth.controllers.api_public.request', dummy_request), \
                patch('odoo.addons.acpec_mobile_auth.controllers.api_common.request', dummy_request), \
                patch('odoo.addons.acpec_mobile_auth_otp.controllers.api_otp.request', dummy_request):
            signup_result = controller.signup(
                name='Client OTP E2E',
                signup_identifier='32524656',
                secret_code='1234',
                company_id=self.env.company.id,
                email='client-e2e@example.com',
            )

            self.assertTrue(signup_result['ok'])
            signup_data = signup_result['data']
            self.assertEqual(signup_data['signup_identifier_type'], 'phone')
            self.assertEqual(signup_data['otp_delivery'], 'dev_fixed_otp')
            self.assertNotIn('otp_dev_code', signup_data)
            self.assertTrue(signup_data['otp_challenge_id'])

            device_uid = 'ft-android-test-register-32524656'
            verify_result = otp_controller.verify_otp(
                challenge_id=signup_data['otp_challenge_id'],
                identifier='32524656',
                code='000000',
                name='Client OTP E2E',
                secret_code='1234',
                company_id=self.env.company.id,
                email='client-e2e@example.com',
                device_uid=device_uid,
                device_name='Flutter Android',
                platform='android',
                app_version='test',
            )

        self.assertTrue(verify_result['ok'])
        session_data = verify_result['data']
        self.assertTrue(session_data['access_token'])
        self.assertTrue(session_data['refresh_token'])
        self.assertTrue(session_data['session_ref'])
        self.assertTrue(session_data['pending_approval'])
        self.assertTrue(session_data['account_request_id'])
        self.assertEqual(session_data['device_uid'], device_uid)
        self.assertEqual(session_data['device_trust_state'], 'pending_trust')

        user = self.env['res.users'].sudo().search([('login', '=', '32524656')], limit=1)
        self.assertTrue(user.active)
        self.assertEqual(user.login, '32524656')
        self.assertEqual(user.mobile_phone, '32524656')
        self.assertEqual(user.mobile_state, 'self_registered')
        self.assertTrue(user.mobile_pin_set_at)
        self.assertTrue(user.mobile_pin_set)
        self.assertFalse(user.mobile_pin_required)
        self.assertTrue(session_data['mobile_pin_set'])
        self.assertFalse(session_data['mobile_pin_required'])
        user.check_mobile_pin('1234')

        account_request = self.env['acpec.mobile.auth.account.request'].sudo().search([
            ('user_id', '=', user.id),
        ], order='id desc', limit=1)
        self.assertTrue(account_request)
        self.assertEqual(account_request.state, 'approved')

        session = self.env['acpec.mobile.session'].sudo().search([
            ('name', '=', session_data['session_ref']),
        ], limit=1)
        self.assertTrue(session)
        self.assertEqual(session.device_uid, device_uid)
        self.assertEqual(session.device_trust_state, 'pending_trust')
        self.assertTrue(session.is_device_approval_candidate)

    def test_legacy_mobile_user_migration_requires_new_pin_without_touching_internal_users(self):
        mobile_baseline_group_ids = []
        for xmlid in (
            'base.group_portal',
            'acpec_mobile_auth.group_mobile_auth_user',
        ):
            group = self.env.ref(xmlid, raise_if_not_found=False)
            if group:
                mobile_baseline_group_ids.append(group.id)

        mobile_partner = self.env['res.partner'].create({'name': 'Legacy Mobile'})
        mobile_group = self.env.ref('acpec_mobile_auth.group_mobile_auth_user')
        mobile_user = self.env['res.users'].sudo().with_context(no_reset_password=True).create({
            'name': 'Legacy Mobile',
            'login': 'legacy.mobile@example.com',
            'password': '1234',
            'partner_id': mobile_partner.id,
            'company_id': self.env.company.id,
            'company_ids': [(6, 0, [self.env.company.id])],
            'group_ids': [(6, 0, mobile_baseline_group_ids)],
            'mobile_phone': '32524001',
            'mobile_state': 'approved',
            'mobile_only': True,
        })

        internal_partner = self.env['res.partner'].create({'name': 'Internal User'})
        internal_user = self.env['res.users'].sudo().with_context(no_reset_password=True).create({
            'name': 'Internal User',
            'login': 'internal.pin@example.com',
            'password': '1234',
            'partner_id': internal_partner.id,
            'company_id': self.env.company.id,
            'company_ids': [(6, 0, [self.env.company.id])],
            'group_ids': [(6, 0, [self.env.ref('base.group_user').id])],
        })

        migrated = self.env['res.users'].sudo()._acpec_migrate_legacy_mobile_pin_credentials()

        self.assertGreaterEqual(migrated, 1)
        mobile_user.invalidate_recordset(['mobile_pin_set', 'mobile_pin_required', 'mobile_pin_hash', 'mobile_pin_salt'])
        internal_user.invalidate_recordset(['mobile_pin_required'])
        self.assertFalse(mobile_user.mobile_pin_set)
        self.assertTrue(mobile_user.mobile_pin_required)
        self.assertFalse(mobile_user.mobile_pin_hash)
        self.assertFalse(mobile_user.mobile_pin_salt)
        self.assertFalse(internal_user.mobile_pin_required)



    def test_rate_limit_rejects_same_identifier_per_minute(self):
        icp = self.env['ir.config_parameter'].sudo()
        self._set_security_setting('acpec_mobile_auth.otp_dev_mode', 'False')
        icp.set_param('SMS_PROVIDER', '')
        icp.set_param('SMS_VALIDATION_KEY', '')
        icp.set_param('SMS_TOKEN', '')
        icp.set_param('SMS_URL', '')
        self._set_security_setting('acpec_mobile_auth.otp_limit_identifier_per_minute', '1')
        self._set_security_setting('acpec_mobile_auth.otp_limit_identifier_per_day', '100')
        self._set_security_setting('acpec_mobile_auth.otp_limit_ip_per_hour', '100')
        self._set_security_setting('acpec_mobile_auth.otp_limit_register_ip_per_day', '100')

        self.env['acpec.mobile.auth.otp'].sudo().request_otp(
            '32524990',
            purpose='register',
            request_ip='10.0.0.10',
        )

        with self.assertRaisesRegex(ValidationError, 'Trop de demandes OTP'):
            self.env['acpec.mobile.auth.otp'].sudo().request_otp(
                '32524990',
                purpose='register',
                request_ip='10.0.0.10',
            )

    def test_request_otp_route_returns_rate_limited_code(self):
        icp = self.env['ir.config_parameter'].sudo()
        self._set_security_setting('acpec_mobile_auth.otp_dev_mode', 'False')
        icp.set_param('SMS_PROVIDER', '')
        icp.set_param('SMS_VALIDATION_KEY', '')
        icp.set_param('SMS_TOKEN', '')
        icp.set_param('SMS_URL', '')
        self._set_security_setting('acpec_mobile_auth.otp_limit_identifier_per_minute', '1')
        self._set_security_setting('acpec_mobile_auth.otp_limit_identifier_per_day', '100')
        self._set_security_setting('acpec_mobile_auth.otp_limit_ip_per_hour', '100')
        self._set_security_setting('acpec_mobile_auth.otp_limit_register_ip_per_day', '100')

        self.env['acpec.mobile.auth.otp'].sudo().request_otp(
            '32524989',
            purpose='register',
            request_ip='10.0.0.9',
        )

        controller = AcpecMobileAuthOtpApi()
        controller._require_keys = lambda params, keys: None
        controller._get_clean_str = lambda params, key: str(params.get(key) or '').strip()
        dummy_httprequest = SimpleNamespace(
            remote_addr='10.0.0.9',
            headers={'User-Agent': 'pytest'},
        )
        dummy_request = SimpleNamespace(env=self.env, cr=self.env.cr, httprequest=dummy_httprequest)

        with patch('odoo.addons.acpec_mobile_auth.controllers.api_common.request', dummy_request), \
                patch('odoo.addons.acpec_mobile_auth_otp.controllers.api_otp.request', dummy_request):
            result = controller.request_otp(
                identifier='32524989',
                purpose='register',
            )

        self.assertFalse(result['ok'])
        self.assertEqual(result['error']['code'], 'RATE_LIMITED')
        self.assertIn('Trop de demandes OTP', result['error']['message'])

    def test_rate_limit_rejects_same_identifier_per_day(self):
        icp = self.env['ir.config_parameter'].sudo()
        self._set_security_setting('acpec_mobile_auth.otp_dev_mode', 'False')
        icp.set_param('SMS_PROVIDER', '')
        icp.set_param('SMS_VALIDATION_KEY', '')
        icp.set_param('SMS_TOKEN', '')
        icp.set_param('SMS_URL', '')
        self._set_security_setting('acpec_mobile_auth.otp_limit_identifier_per_minute', '0')
        self._set_security_setting('acpec_mobile_auth.otp_limit_identifier_per_day', '1')
        self._set_security_setting('acpec_mobile_auth.otp_limit_ip_per_hour', '100')
        self._set_security_setting('acpec_mobile_auth.otp_limit_register_ip_per_day', '100')

        self.env['acpec.mobile.auth.otp'].sudo().request_otp(
            '32524991',
            purpose='register',
            request_ip='10.0.0.11',
        )

        with self.assertRaisesRegex(ValidationError, 'Trop de demandes OTP'):
            self.env['acpec.mobile.auth.otp'].sudo().request_otp(
                '32524991',
                purpose='register',
                request_ip='10.0.0.12',
            )

    def test_rate_limit_rejects_ip_per_hour(self):
        icp = self.env['ir.config_parameter'].sudo()
        self._set_security_setting('acpec_mobile_auth.otp_dev_mode', 'False')
        icp.set_param('SMS_PROVIDER', '')
        icp.set_param('SMS_VALIDATION_KEY', '')
        icp.set_param('SMS_TOKEN', '')
        icp.set_param('SMS_URL', '')
        self._set_security_setting('acpec_mobile_auth.otp_limit_identifier_per_minute', '0')
        self._set_security_setting('acpec_mobile_auth.otp_limit_identifier_per_day', '100')
        self._set_security_setting('acpec_mobile_auth.otp_limit_ip_per_hour', '1')
        self._set_security_setting('acpec_mobile_auth.otp_limit_register_ip_per_day', '100')

        self.env['acpec.mobile.auth.otp'].sudo().request_otp(
            '32524992',
            purpose='register',
            request_ip='10.0.0.21',
        )

        with self.assertRaisesRegex(ValidationError, 'Trop de demandes OTP'):
            self.env['acpec.mobile.auth.otp'].sudo().request_otp(
                '32524993',
                purpose='register',
                request_ip='10.0.0.21',
            )

    def test_rate_limit_rejects_register_ip_per_day(self):
        icp = self.env['ir.config_parameter'].sudo()
        self._set_security_setting('acpec_mobile_auth.otp_dev_mode', 'False')
        icp.set_param('SMS_PROVIDER', '')
        icp.set_param('SMS_VALIDATION_KEY', '')
        icp.set_param('SMS_TOKEN', '')
        icp.set_param('SMS_URL', '')
        self._set_security_setting('acpec_mobile_auth.otp_limit_identifier_per_minute', '0')
        self._set_security_setting('acpec_mobile_auth.otp_limit_identifier_per_day', '100')
        self._set_security_setting('acpec_mobile_auth.otp_limit_ip_per_hour', '100')
        self._set_security_setting('acpec_mobile_auth.otp_limit_register_ip_per_day', '1')

        self.env['acpec.mobile.auth.otp'].sudo().request_otp(
            '32524994',
            purpose='register',
            request_ip='10.0.0.31',
        )

        with self.assertRaisesRegex(ValidationError, 'Trop de demandes OTP'):
            self.env['acpec.mobile.auth.otp'].sudo().request_otp(
                '32524995',
                purpose='register',
                request_ip='10.0.0.31',
            )
