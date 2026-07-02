# -*- coding: utf-8 -*-
import os
from types import SimpleNamespace
from unittest.mock import patch


def _acpec_test_mobile_phone(label):
    """Return a deterministic canonical 8-digit mobile phone for test labels."""
    value = 2166136261
    for char in str(label):
        value ^= ord(char)
        value = (value * 16777619) % 10000000
    return "3%07d" % value

from odoo.exceptions import AccessError
from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_mobile_auth_otp.controllers.api_otp import AcpecMobileAuthOtpApi


@tagged('post_install', '-at_install')
class TestMobilePinResetOtp(TransactionCase):

    def _group_ids(self):
        xmlids = (
            'base.group_portal',
            'acpec_mobile_auth.group_mobile_auth_user',
        )
        return [
            self.env.ref(xmlid).id
            for xmlid in xmlids
            if self.env.ref(xmlid, raise_if_not_found=False)
        ]

    def _create_mobile_user(self, login='reset-pin-otp-30d@example.com', mobile_phone='32524658'):
        user_model = self.env['res.users'].sudo().with_context(
            acpec_mobile_allow_password_write=True,
            no_reset_password=True,
        )
        user = user_model.create({
            'name': login,
            'login': mobile_phone,
            'email': login,
            'mobile_phone': mobile_phone,
            'active': True,
            'mobile_only': True,
            'mobile_state': 'approved',
            'password': user_model._acpec_mobile_unusable_password(),
            'group_ids': [(6, 0, self._group_ids())],
        })
        user.set_mobile_pin('1234')
        return user

    def _fake_request(self):
        return SimpleNamespace(
            env=self.env,
            httprequest=SimpleNamespace(
                remote_addr='127.0.0.1',
                headers={'User-Agent': 'odoo-test'},
            ),
        )

    def _set_security_param(self, key, value):
        settings = self.env['acpec.mobile.security.setting'].sudo()
        settings.search([('key', '=', key)]).unlink()
        settings.create({
            'key': key,
            'value': str(value),
            'active': True,
        })

    def _expect_access_error_without_savepoint(self, func, *args, **kwargs):
        try:
            func(*args, **kwargs)
        except AccessError:
            return
        self.fail('AccessError attendu mais non levé.')

    def _request_otp_dev(self, user, purpose='reset'):
        with patch.dict(os.environ, {
            'ACPEC_ENV': 'dev',
            'ODOO_ENV': '',
            'ENV': '',
            'ACPEC_FUELTOKEN_DEV_MODE': '1',
            'ACPEC_FUELTOKEN_TEST_MODE': '',
            'SMS_PROVIDER': '',
            'SMS_VALIDATION_KEY': '',
            'SMS_TOKEN': '',
            'SMS_URL': '',
        }, clear=False):
            return self.env['acpec.mobile.auth.otp'].sudo().request_otp(
                user.login,
                purpose=purpose,
            )

    def _call_request_otp(self, **kwargs):
        fake_request = self._fake_request()
        controller = AcpecMobileAuthOtpApi()
        with patch.dict(os.environ, {
            'ACPEC_ENV': 'dev',
            'ODOO_ENV': '',
            'ENV': '',
            'ACPEC_FUELTOKEN_DEV_MODE': '1',
            'ACPEC_FUELTOKEN_TEST_MODE': '',
            'SMS_PROVIDER': '',
            'SMS_VALIDATION_KEY': '',
            'SMS_TOKEN': '',
            'SMS_URL': '',
        }, clear=False), \
             patch('odoo.addons.acpec_mobile_auth_otp.controllers.api_otp.request', fake_request), \
             patch('odoo.addons.acpec_mobile_auth.controllers.api_common.request', fake_request):
            return controller.request_otp(**kwargs)

    def _call_verify_otp(self, **kwargs):
        fake_request = self._fake_request()
        controller = AcpecMobileAuthOtpApi()
        with patch.dict(os.environ, {
            'ACPEC_ENV': 'dev',
            'ODOO_ENV': '',
            'ENV': '',
            'ACPEC_FUELTOKEN_DEV_MODE': '1',
            'ACPEC_FUELTOKEN_TEST_MODE': '',
            'SMS_PROVIDER': '',
            'SMS_VALIDATION_KEY': '',
            'SMS_TOKEN': '',
            'SMS_URL': '',
        }, clear=False), \
             patch('odoo.addons.acpec_mobile_auth_otp.controllers.api_otp.request', fake_request), \
             patch('odoo.addons.acpec_mobile_auth.controllers.api_common.request', fake_request):
            return controller.verify_otp(**kwargs)

    def _assert_old_pin_works_and_new_pin_fails(self, user, old_pin='1234', new_pin='5678'):
        self.assertTrue(user.check_mobile_pin(old_pin, purpose='old_pin_still_valid'))
        with self.assertRaises(AccessError):
            user.check_mobile_pin(new_pin, purpose='new_pin_must_not_be_active')
        user.sudo().write({'mobile_pin_locked_until': False})

    def test_request_otp_forgot_pin_aliases_create_reset_challenge(self):
        for idx, alias in enumerate(('forgot_password', 'forgot_pin'), start=1):
            user = self._create_mobile_user(
                'forgot-pin-alias-%s-30d@example.com' % alias.replace('_', '-'),
                mobile_phone='3252476%s' % idx,
            )

            self._call_request_otp(
                identifier=user.login,
                purpose=alias,
            )

            challenge = self.env['acpec.mobile.auth.otp'].sudo().search([
                ('identifier', '=', user.login),
            ], order='id desc', limit=1)

            self.assertTrue(challenge)
            self.assertEqual(challenge.purpose, 'reset')
            self.assertEqual(challenge.user_id, user)

    def test_action_reset_mobile_pin_clears_pin_without_defining_new_one(self):
        user = self._create_mobile_user('admin-reset-pin-30d@example.com')

        user.action_reset_mobile_pin()
        user.invalidate_recordset([
            'mobile_pin_required',
            'mobile_pin_set',
            'mobile_pin_hash',
            'mobile_pin_salt',
            'mobile_pin_failed_count',
            'mobile_pin_locked_until',
        ])

        self.assertTrue(user.mobile_pin_required)
        self.assertFalse(user.mobile_pin_set)
        self.assertFalse(user.mobile_pin_hash)
        self.assertFalse(user.mobile_pin_salt)
        self.assertEqual(user.mobile_pin_failed_count, 0)
        self.assertFalse(user.mobile_pin_locked_until)

    def test_verify_otp_reset_restores_pin_after_hard_block_with_secret_code(self):
        self._set_security_param('acpec_mobile_auth.mobile_pin_max_attempts', 2)
        self._set_security_param('acpec_mobile_auth.mobile_pin_lock_seconds', 30)
        self._set_security_param('acpec_mobile_auth.mobile_pin_hard_block_attempts', 10)

        user = self._create_mobile_user()

        for attempt in range(1, 10):
            self._expect_access_error_without_savepoint(
                user.check_mobile_pin,
                '9999',
                purpose='wrong_pin_%s' % attempt,
            )
            user.sudo().write({'mobile_pin_locked_until': False})

        self._expect_access_error_without_savepoint(
            user.check_mobile_pin,
            '9999',
            purpose='wrong_pin_hard_block',
        )

        user.invalidate_recordset([
            'mobile_pin_required',
            'mobile_pin_set',
            'mobile_pin_hash',
            'mobile_pin_salt',
        ])
        self.assertTrue(user.mobile_pin_required)
        self.assertFalse(user.mobile_pin_set)

        challenge, code = self._request_otp_dev(user, purpose='reset')

        self._call_verify_otp(
            challenge_id=challenge.id,
            code=code,
            secret_code='5678',
            device_uid='reset-pin-device-30d',
            platform='android',
        )

        user.invalidate_recordset([
            'mobile_pin_required',
            'mobile_pin_set',
            'mobile_pin_failed_count',
            'mobile_pin_locked_until',
        ])
        self.assertFalse(user.mobile_pin_required)
        self.assertTrue(user.mobile_pin_set)
        self.assertEqual(user.mobile_pin_failed_count, 0)
        self.assertFalse(user.mobile_pin_locked_until)
        self.assertTrue(user.check_mobile_pin('5678', purpose='after_reset'))

    def test_verify_otp_reset_rejects_action_code_alias_without_consuming_otp(self):
        user = self._create_mobile_user('reset-alias-action-code-30d@example.com')
        challenge, code = self._request_otp_dev(user, purpose='reset')

        self._call_verify_otp(
            challenge_id=challenge.id,
            code=code,
            action_code='5678',
            device_uid='reset-alias-device-30d',
            platform='android',
        )

        challenge.invalidate_recordset(['state', 'verified_at'])
        self.assertEqual(challenge.state, 'pending')
        self.assertFalse(challenge.verified_at)
        self._assert_old_pin_works_and_new_pin_fails(user)

        self._call_verify_otp(
            challenge_id=challenge.id,
            code=code,
            secret_code='5678',
            device_uid='reset-alias-device-30d',
            platform='android',
        )

        user.invalidate_recordset(['mobile_pin_set', 'mobile_pin_required'])
        self.assertTrue(user.mobile_pin_set)
        self.assertFalse(user.mobile_pin_required)
        self.assertTrue(user.check_mobile_pin('5678', purpose='reset_after_alias_reuse'))

    def test_verify_otp_reset_rejects_other_pin_aliases_without_consuming_otp(self):
        aliases = ('pin', 'action_pin', 'new_pin')
        for idx, alias in enumerate(aliases, start=1):
            user = self._create_mobile_user(
                'reset-alias-%s-30d@example.com' % alias.replace('_', '-'),
                mobile_phone='3252465%s' % idx,
            )
            challenge, code = self._request_otp_dev(user, purpose='reset')

            self._call_verify_otp(
                challenge_id=challenge.id,
                code=code,
                **{
                    alias: '5678',
                    'device_uid': 'reset-alias-%s-device-30d' % alias,
                    'platform': 'android',
                }
            )

            challenge.invalidate_recordset(['state', 'verified_at'])
            self.assertEqual(challenge.state, 'pending')
            self.assertFalse(challenge.verified_at)
            self._assert_old_pin_works_and_new_pin_fails(user)

    def test_verify_otp_login_with_secret_code_does_not_reset_pin(self):
        user = self._create_mobile_user('reset-login-purpose-30d@example.com')
        challenge, code = self._request_otp_dev(user, purpose='login')

        self._call_verify_otp(
            challenge_id=challenge.id,
            code=code,
            secret_code='5678',
            device_uid='login-purpose-device-30d',
            platform='android',
        )

        challenge.invalidate_recordset(['state', 'verified_at'])
        self.assertEqual(challenge.state, 'verified')
        self.assertTrue(challenge.verified_at)
        self._assert_old_pin_works_and_new_pin_fails(user)

    def test_verify_otp_reset_malformed_secret_code_does_not_consume_otp(self):
        user = self._create_mobile_user('reset-malformed-pin-30d@example.com')
        challenge, code = self._request_otp_dev(user, purpose='reset')

        self._call_verify_otp(
            challenge_id=challenge.id,
            code=code,
            secret_code='12',
            device_uid='reset-malformed-device-30d',
            platform='android',
        )

        challenge.invalidate_recordset(['state', 'verified_at'])
        self.assertEqual(challenge.state, 'pending')
        self.assertFalse(challenge.verified_at)
        self._assert_old_pin_works_and_new_pin_fails(user)

        self._call_verify_otp(
            challenge_id=challenge.id,
            code=code,
            secret_code='5678',
            device_uid='reset-malformed-device-30d',
            platform='android',
        )

        user.invalidate_recordset(['mobile_pin_set', 'mobile_pin_required'])
        self.assertTrue(user.mobile_pin_set)
        self.assertFalse(user.mobile_pin_required)
        self.assertTrue(user.check_mobile_pin('5678', purpose='reset_after_malformed_reuse'))
