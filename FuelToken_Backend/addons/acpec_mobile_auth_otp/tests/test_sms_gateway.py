import hashlib
from types import SimpleNamespace
from unittest.mock import patch

from odoo.exceptions import AccessError, ValidationError
from odoo.tests import TransactionCase, tagged
from odoo.addons.acpec_mobile_auth.controllers.api_public import AcpecMobileAuthApiPublic
from odoo.addons.acpec_mobile_auth_otp.controllers.api_otp import AcpecMobileAuthOtpApi


@tagged('-at_install', 'post_install')
class TestAcpecMobileAuthOtpSms(TransactionCase):

    def setUp(self):
        super().setUp()
        # Keep legacy OTP tests independent from historical rows in the dev DB.
        # Dedicated rate-limit tests override these values explicitly.
        icp = self.env['ir.config_parameter'].sudo()
        icp.set_param('acpec_mobile_auth.otp_limit_identifier_per_minute', '0')
        icp.set_param('acpec_mobile_auth.otp_limit_identifier_per_day', '0')
        icp.set_param('acpec_mobile_auth.otp_limit_ip_per_hour', '0')
        icp.set_param('acpec_mobile_auth.otp_limit_register_ip_per_day', '0')
        icp.set_param('acpec_mobile_auth.otp_code_length', '6')
        icp.set_param('acpec_mobile_auth.otp_dev_mode', '0')

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
        icp.set_param('acpec_mobile_auth.otp_dev_mode', '0')

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

    def test_request_otp_keeps_dev_mode_without_sms_config(self):
        icp = self.env['ir.config_parameter'].sudo()
        icp.set_param('acpec_mobile_auth.otp_dev_mode', 'True')
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
        icp.set_param('acpec_mobile_auth.otp_dev_mode', 'True')
        icp.set_param('acpec_mobile_auth.otp_request_cooldown_seconds', '0')
        icp.set_param('acpec_mobile_auth.otp_limit_identifier_per_minute', '0')
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
        icp = self.env['ir.config_parameter'].sudo()
        icp.set_param('SMS_PROVIDER', '')
        icp.set_param('SMS_VALIDATION_KEY', '')
        icp.set_param('SMS_TOKEN', '')
        icp.set_param('SMS_URL', '')
        icp.set_param('acpec_mobile_auth.otp_dev_mode', 'True')

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
        self.assertEqual(request_data['otp_delivery'], 'dev_response')
        self.assertFalse(self.env['acpec.mobile.auth.account.request'].sudo().search([
            ('signup_identifier', '=', '32524655'),
        ], limit=1))

        with patch('odoo.addons.acpec_mobile_auth.controllers.api_common.request', dummy_request), \
                patch('odoo.addons.acpec_mobile_auth_otp.controllers.api_otp.request', dummy_request):
            verify_result = otp_controller.verify_otp(
                challenge_id=request_data['otp_challenge_id'],
                identifier='32524655',
                code=request_data['otp_dev_code'],
                name='Client OTP',
                secret_code='1234',
                company_id=self.env.company.id,
            )

        self.assertTrue(verify_result['ok'])
        session_data = verify_result['data']
        self.assertTrue(session_data['access_token'])
        self.assertTrue(session_data['refresh_token'])
        self.assertNotIn('pending_approval', session_data)

        user = self.env['res.users'].sudo().search([('login', '=', '32524655')], limit=1)
        self.assertTrue(user)
        self.assertTrue(user.active)
        self.assertEqual(user.mobile_state, 'approved')
        self.assertTrue(user.mobile_pin_set)
        self.assertFalse(user.mobile_pin_required)
        self.assertTrue(user.mobile_pin_hash)
        self.assertTrue(user.mobile_pin_salt)
        user.check_mobile_pin('1234')

        account_request = self.env['acpec.mobile.auth.account.request'].sudo().search([
            ('user_id', '=', user.id),
        ], order='id desc', limit=1)
        self.assertFalse(account_request)

    def test_signup_route_returns_register_otp_payload_for_phone(self):
        self.env.company.write({'acpec_mobile_auth_enabled': True})
        icp = self.env['ir.config_parameter'].sudo()
        icp.set_param('SMS_PROVIDER', 'chinguisoft')
        icp.set_param('SMS_VALIDATION_KEY', 'test-validation-key')
        icp.set_param('SMS_TOKEN', 'test-validation-token')
        icp.set_param('SMS_URL', 'https://chinguisoft.com/api/sms/validation')
        icp.set_param('SMS_DEFAULT_LANG', 'fr')
        icp.set_param('acpec_mobile_auth.otp_dev_mode', '0')

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
        controller._get_config_bool = lambda key, default=False: False
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
        icp = self.env['ir.config_parameter'].sudo()
        icp.set_param('SMS_PROVIDER', 'chinguisoft')
        icp.set_param('SMS_VALIDATION_KEY', 'test-validation-key')
        icp.set_param('SMS_TOKEN', 'test-validation-token')
        icp.set_param('SMS_URL', 'https://chinguisoft.com/api/sms/validation')
        icp.set_param('SMS_DEFAULT_LANG', 'fr')
        icp.set_param('acpec_mobile_auth.otp_dev_mode', 'True')

        class FakeResponse:
            status_code = 200
            text = '{"status": "ok", "message_id": "sms-test-1"}'

            def json(self):
                return {'status': 'ok', 'message_id': 'sms-test-1'}

        controller = AcpecMobileAuthApiPublic()
        otp_controller = AcpecMobileAuthOtpApi()
        controller._require_keys = lambda params, keys: None
        controller._get_clean_str = lambda params, key: str(params.get(key) or '').strip()
        controller._get_optional_int = lambda params, key, default=False: int(params.get(key) or default)
        controller._get_company = lambda company_id=False: self.env.company
        controller._get_config_bool = lambda key, default=False: True if key == 'acpec_mobile_auth.otp_dev_mode' else False
        dummy_httprequest = SimpleNamespace(
            remote_addr='127.0.0.1',
            headers={'User-Agent': 'pytest'},
        )
        dummy_request = SimpleNamespace(env=self.env, cr=self.env.cr, httprequest=dummy_httprequest)

        with patch('odoo.addons.acpec_mobile_auth.controllers.api_public.request', dummy_request), \
                patch('odoo.addons.acpec_mobile_auth.controllers.api_common.request', dummy_request), \
                patch('odoo.addons.acpec_mobile_auth_otp.controllers.api_otp.request', dummy_request), \
                patch('odoo.addons.acpec_mobile_auth_otp.models.sms_gateway.requests.post', return_value=FakeResponse()):
            signup_result = controller.signup(
                name='Client OTP',
                signup_identifier='32524657',
                secret_code='1234',
                company_id=self.env.company.id,
                email='client2@example.com',
            )

        signup_data = signup_result['data']
        challenge_id = signup_data['otp_challenge_id']
        otp_code = signup_data['otp_dev_code']

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
            )

        self.assertTrue(verify_result['ok'])
        session_data = verify_result['data']
        self.assertTrue(session_data['access_token'])
        self.assertTrue(session_data['refresh_token'])

        user = self.env['res.users'].sudo().search([('login', '=', '32524657')], limit=1)
        self.assertTrue(user.active)
        self.assertEqual(user.mobile_state, 'approved')
        self.assertTrue(user.mobile_pin_set_at)
        self.assertTrue(user.mobile_pin_set)
        self.assertFalse(user.mobile_pin_required)
        self.assertTrue(session_data['mobile_pin_set'])
        self.assertFalse(session_data['mobile_pin_required'])
        user.check_mobile_pin('1234')
        with self.assertRaises(AccessError):
            user.check_mobile_pin('9999')

    def test_signup_then_verify_register_otp_e2e_without_sms_provider(self):
        self.env.company.write({'acpec_mobile_auth_enabled': True})
        icp = self.env['ir.config_parameter'].sudo()
        icp.set_param('acpec_mobile_auth.otp_dev_mode', 'True')
        icp.set_param('SMS_PROVIDER', '')
        icp.set_param('SMS_VALIDATION_KEY', '')
        icp.set_param('SMS_TOKEN', '')
        icp.set_param('SMS_URL', '')

        controller = AcpecMobileAuthApiPublic()
        otp_controller = AcpecMobileAuthOtpApi()
        controller._require_keys = lambda params, keys: None
        controller._get_clean_str = lambda params, key: str(params.get(key) or '').strip()
        controller._get_optional_int = lambda params, key, default=False: int(params.get(key) or default)
        controller._get_company = lambda company_id=False: self.env.company
        controller._get_config_bool = lambda key, default=False: True if key == 'acpec_mobile_auth.otp_dev_mode' else False
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
            self.assertEqual(signup_data['otp_delivery'], 'dev_response')
            self.assertTrue(signup_data['otp_dev_code'])
            self.assertTrue(signup_data['otp_challenge_id'])

            verify_result = otp_controller.verify_otp(
                challenge_id=signup_data['otp_challenge_id'],
                identifier='32524656',
                code=signup_data['otp_dev_code'],
                name='Client OTP E2E',
                secret_code='1234',
                company_id=self.env.company.id,
                email='client-e2e@example.com',
            )

        self.assertTrue(verify_result['ok'])
        session_data = verify_result['data']
        self.assertTrue(session_data['access_token'])
        self.assertTrue(session_data['refresh_token'])
        self.assertTrue(session_data['session_ref'])

        user = self.env['res.users'].sudo().search([('login', '=', '32524656')], limit=1)
        self.assertTrue(user.active)
        self.assertEqual(user.mobile_state, 'approved')
        self.assertTrue(user.mobile_pin_set_at)
        self.assertTrue(user.mobile_pin_set)
        self.assertFalse(user.mobile_pin_required)
        self.assertTrue(session_data['mobile_pin_set'])
        self.assertFalse(session_data['mobile_pin_required'])
        user.check_mobile_pin('1234')

        account_request = self.env['acpec.mobile.auth.account.request'].sudo().search([
            ('user_id', '=', user.id),
        ], order='id desc', limit=1)
        # The OTP registration flow creates the mobile account directly after
        # successful verification; it does not leave an account.request record.
        self.assertFalse(account_request)


    def test_legacy_mobile_user_migration_requires_new_pin_without_touching_internal_users(self):
        mobile_partner = self.env['res.partner'].create({'name': 'Legacy Mobile'})
        mobile_group = self.env.ref('acpec_mobile_auth.group_mobile_auth_user')
        mobile_user = self.env['res.users'].sudo().with_context(no_reset_password=True).create({
            'name': 'Legacy Mobile',
            'login': 'legacy.mobile@example.com',
            'password': '1234',
            'partner_id': mobile_partner.id,
            'company_id': self.env.company.id,
            'company_ids': [(6, 0, [self.env.company.id])],
            'group_ids': [(6, 0, [mobile_group.id])],
            'mobile_phone': '32524001',
            'mobile_state': 'approved',
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
        icp.set_param('acpec_mobile_auth.otp_dev_mode', 'True')
        icp.set_param('SMS_PROVIDER', '')
        icp.set_param('SMS_VALIDATION_KEY', '')
        icp.set_param('SMS_TOKEN', '')
        icp.set_param('SMS_URL', '')
        icp.set_param('acpec_mobile_auth.otp_limit_identifier_per_minute', '1')
        icp.set_param('acpec_mobile_auth.otp_limit_identifier_per_day', '100')
        icp.set_param('acpec_mobile_auth.otp_limit_ip_per_hour', '100')
        icp.set_param('acpec_mobile_auth.otp_limit_register_ip_per_day', '100')

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
        icp.set_param('acpec_mobile_auth.otp_dev_mode', 'True')
        icp.set_param('SMS_PROVIDER', '')
        icp.set_param('SMS_VALIDATION_KEY', '')
        icp.set_param('SMS_TOKEN', '')
        icp.set_param('SMS_URL', '')
        icp.set_param('acpec_mobile_auth.otp_limit_identifier_per_minute', '1')
        icp.set_param('acpec_mobile_auth.otp_limit_identifier_per_day', '100')
        icp.set_param('acpec_mobile_auth.otp_limit_ip_per_hour', '100')
        icp.set_param('acpec_mobile_auth.otp_limit_register_ip_per_day', '100')

        self.env['acpec.mobile.auth.otp'].sudo().request_otp(
            '32524989',
            purpose='register',
            request_ip='10.0.0.9',
        )

        controller = AcpecMobileAuthOtpApi()
        controller._require_keys = lambda params, keys: None
        controller._get_clean_str = lambda params, key: str(params.get(key) or '').strip()
        controller._get_config_bool = lambda key, default=False: False
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
        icp.set_param('acpec_mobile_auth.otp_dev_mode', 'True')
        icp.set_param('SMS_PROVIDER', '')
        icp.set_param('SMS_VALIDATION_KEY', '')
        icp.set_param('SMS_TOKEN', '')
        icp.set_param('SMS_URL', '')
        icp.set_param('acpec_mobile_auth.otp_limit_identifier_per_minute', '0')
        icp.set_param('acpec_mobile_auth.otp_limit_identifier_per_day', '1')
        icp.set_param('acpec_mobile_auth.otp_limit_ip_per_hour', '100')
        icp.set_param('acpec_mobile_auth.otp_limit_register_ip_per_day', '100')

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
        icp.set_param('acpec_mobile_auth.otp_dev_mode', 'True')
        icp.set_param('SMS_PROVIDER', '')
        icp.set_param('SMS_VALIDATION_KEY', '')
        icp.set_param('SMS_TOKEN', '')
        icp.set_param('SMS_URL', '')
        icp.set_param('acpec_mobile_auth.otp_limit_identifier_per_minute', '0')
        icp.set_param('acpec_mobile_auth.otp_limit_identifier_per_day', '100')
        icp.set_param('acpec_mobile_auth.otp_limit_ip_per_hour', '1')
        icp.set_param('acpec_mobile_auth.otp_limit_register_ip_per_day', '100')

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
        icp.set_param('acpec_mobile_auth.otp_dev_mode', 'True')
        icp.set_param('SMS_PROVIDER', '')
        icp.set_param('SMS_VALIDATION_KEY', '')
        icp.set_param('SMS_TOKEN', '')
        icp.set_param('SMS_URL', '')
        icp.set_param('acpec_mobile_auth.otp_limit_identifier_per_minute', '0')
        icp.set_param('acpec_mobile_auth.otp_limit_identifier_per_day', '100')
        icp.set_param('acpec_mobile_auth.otp_limit_ip_per_hour', '100')
        icp.set_param('acpec_mobile_auth.otp_limit_register_ip_per_day', '1')

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

