import hashlib
from types import SimpleNamespace
from unittest.mock import patch

from odoo.tests import TransactionCase, tagged
from odoo.addons.acpec_mobile_auth.controllers.api_public import AcpecMobileAuthApiPublic
from odoo.addons.acpec_mobile_auth_otp.controllers.api_otp import AcpecMobileAuthOtpApi


@tagged('-at_install', 'post_install')
class TestAcpecMobileAuthOtpSms(TransactionCase):

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

    def test_request_otp_posts_validation_sms_to_chinguisoft(self):
        icp = self.env['ir.config_parameter'].sudo()
        icp.set_param('SMS_PROVIDER', 'chinguisoft')
        icp.set_param('SMS_VALIDATION_KEY', 'test-validation-key')
        icp.set_param('SMS_TOKEN', 'test-validation-token')
        icp.set_param('SMS_URL', 'https://chinguisoft.com/api/sms/validation')
        icp.set_param('SMS_DEFAULT_LANG', 'fr')

        class FakeResponse:
            status_code = 200
            text = '{"code": 123456, "balance": 99}'

            def json(self):
                return {'code': 123456, 'balance': 99}

        with patch('odoo.addons.acpec_mobile_auth_otp.models.sms_gateway.requests.post', return_value=FakeResponse()) as mocked_post:
            challenge, code = self.env['acpec.mobile.auth.otp'].sudo().request_otp('32524658', purpose='register')

        self.assertTrue(challenge)
        self.assertEqual(challenge.state, 'pending')
        self.assertEqual(challenge.mobile, '32524658')
        self.assertEqual(len(code), 6)
        self.assertFalse(self.env['acpec.mobile.auth.account.request'].sudo().search([
            ('signup_identifier', '=', '32524658'),
            ('state', '=', 'pending'),
        ], limit=1))

        mocked_post.assert_called_once()
        args, kwargs = mocked_post.call_args
        self.assertEqual(args[0], 'https://chinguisoft.com/api/sms/validation/test-validation-key')
        self.assertEqual(kwargs['headers']['Validation-token'], 'test-validation-token')
        self.assertEqual(kwargs['headers']['Content-Type'], 'application/json')
        self.assertEqual(kwargs['json']['phone'], '32524658')
        self.assertEqual(kwargs['json']['lang'], 'fr')
        self.assertEqual(kwargs['json']['code'], code)
        self.assertEqual(kwargs['timeout'], 15)

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
        self.assertEqual(len(code), 6)
        mocked_post.assert_not_called()

    def test_request_otp_cancels_previous_pending_challenge_for_identifier(self):
        icp = self.env['ir.config_parameter'].sudo()
        icp.set_param('acpec_mobile_auth.otp_dev_mode', 'True')
        icp.set_param('acpec_mobile_auth.otp_request_cooldown_seconds', '0')
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
        self.assertEqual(len(code), 6)

        challenge2, code2 = self.env['acpec.mobile.auth.otp'].sudo().request_otp(
            '32524656',
            purpose='register',
        )

        self.assertTrue(challenge2)
        self.assertNotEqual(challenge2.id, challenge.id)
        self.assertEqual(challenge.state, 'cancelled')
        self.assertEqual(challenge2.state, 'pending')
        self.assertEqual(len(code2), 6)

    def test_hash_otp_uses_sha256(self):
        salt = 'test-salt'
        code = '123456'
        expected = hashlib.sha256(f'{salt}:{code}'.encode('utf-8')).hexdigest()

        with patch(
            'odoo.addons.acpec_mobile_auth_otp.models.mobile_auth_otp.hashlib.sha256',
            wraps=hashlib.sha256,
        ):
            actual = self.env['acpec.mobile.auth.otp']._hash_otp(code, salt)

        self.assertEqual(actual, expected)

    def test_register_otp_creates_account_request_only_after_verification(self):
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
                secret_code='123456',
                company_id=self.env.company.id,
            )

        self.assertTrue(verify_result['ok'])
        session_data = verify_result['data']
        self.assertTrue(session_data['access_token'])
        self.assertTrue(session_data['refresh_token'])
        self.assertTrue(session_data['pending_approval'])

        user = self.env['res.users'].sudo().search([('login', '=', '32524655')], limit=1)
        self.assertTrue(user)
        self.assertTrue(user.active)
        self.assertEqual(user.mobile_state, 'pending')

        account_request = self.env['acpec.mobile.auth.account.request'].sudo().search([
            ('user_id', '=', user.id),
            ('state', '=', 'pending'),
        ], order='id desc', limit=1)
        self.assertTrue(account_request)
        self.assertEqual(account_request.signup_identifier, '32524655')

    def test_signup_route_returns_register_otp_payload_for_phone(self):
        self.env.company.write({'acpec_mobile_auth_enabled': True})
        icp = self.env['ir.config_parameter'].sudo()
        icp.set_param('SMS_PROVIDER', 'chinguisoft')
        icp.set_param('SMS_VALIDATION_KEY', 'test-validation-key')
        icp.set_param('SMS_TOKEN', 'test-validation-token')
        icp.set_param('SMS_URL', 'https://chinguisoft.com/api/sms/validation')
        icp.set_param('SMS_DEFAULT_LANG', 'fr')

        class FakeResponse:
            status_code = 200
            text = '{"code": 123456}'

            def json(self):
                return {'code': 123456}

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
                patch('odoo.addons.acpec_mobile_auth_otp.models.sms_gateway.requests.post', return_value=FakeResponse()) as mocked_post:
            result = controller.signup(
                name='Client OTP',
                signup_identifier='32524658',
                secret_code='123456',
                company_id=self.env.company.id,
                email='client@example.com',
            )

        self.assertTrue(result['ok'])
        data = result['data']
        self.assertEqual(data['signup_identifier_type'], 'phone')
        self.assertTrue(data['otp_challenge_id'])
        self.assertEqual(data['otp_delivery'], 'configured_provider')
        mocked_post.assert_called_once()

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
            text = '{"code": 123456}'

            def json(self):
                return {'code': 123456}

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
                secret_code='123456',
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
            )

        self.assertTrue(verify_result['ok'])
        session_data = verify_result['data']
        self.assertTrue(session_data['access_token'])
        self.assertTrue(session_data['refresh_token'])

        user = self.env['res.users'].sudo().search([('login', '=', '32524657')], limit=1)
        self.assertTrue(user.active)
        self.assertEqual(user.mobile_state, 'approved')
        self.assertTrue(user.mobile_pin_set_at)

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
                secret_code='123456',
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

        account_request = self.env['acpec.mobile.auth.account.request'].sudo().search([
            ('user_id', '=', user.id),
        ], order='id desc', limit=1)
        self.assertTrue(account_request)
        self.assertEqual(account_request.state, 'approved')
