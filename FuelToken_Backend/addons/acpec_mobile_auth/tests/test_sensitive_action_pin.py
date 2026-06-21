# -*- coding: utf-8 -*-
from odoo.exceptions import AccessError, ValidationError
from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_mobile_auth.controllers.api_common import AcpecMobileAuthApiCommon


@tagged("post_install", "-at_install")
class TestSensitiveActionPin(TransactionCase):

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

    def _create_mobile_user(self, login='sensitive-pin-21a@example.com'):
        user_model = self.env['res.users'].sudo().with_context(
            acpec_mobile_allow_password_write=True,
            no_reset_password=True,
        )
        user = user_model.create({
            'name': login,
            'login': login,
            'email': login,
            'active': True,
            'mobile_only': True,
            'mobile_state': 'approved',
            'password': user_model._acpec_mobile_unusable_password(),
            'group_ids': [(6, 0, self._group_ids())],
        })
        user.set_mobile_pin('1234')
        return user

    def _trusted_session(self):
        user = self._create_mobile_user()
        token_data = self.env['acpec.mobile.session'].sudo().create_for_user(user, {
            'device_uid': 'sensitive-pin-device-21a',
            'platform': 'android',
        })
        session = token_data['session']
        session.action_trust_device()
        return user, session

    def _controller_for_session(self, session):
        controller = AcpecMobileAuthApiCommon()
        controller._test_env = self.env
        controller._get_mobile_session = lambda required=True: session
        return controller

    def _set_security_param(self, key, value):
        self.env['ir.config_parameter'].sudo().set_param(key, str(value))

    def _expect_access_error_without_savepoint(self, func, *args, **kwargs):
        try:
            func(*args, **kwargs)
        except AccessError:
            return
        self.fail('AccessError attendu mais non levé.')

    def test_sensitive_action_pin_accepts_action_code_on_trusted_device(self):
        user, session = self._trusted_session()
        controller = self._controller_for_session(session)

        allowed_user = controller._require_sensitive_action_pin(
            {'action_code': '1234'},
            purpose='unit_test_sensitive_action',
        )

        self.assertEqual(allowed_user.id, user.id)

    def test_sensitive_action_pin_rejects_missing_code(self):
        user, session = self._trusted_session()
        controller = self._controller_for_session(session)

        with self.assertRaises(ValidationError):
            controller._require_sensitive_action_pin({}, purpose='missing_pin')

    def test_sensitive_action_pin_rejects_wrong_code(self):
        user, session = self._trusted_session()
        controller = self._controller_for_session(session)

        with self.assertRaises(AccessError):
            controller._require_sensitive_action_pin(
                {'action_code': '9999'},
                purpose='wrong_pin',
            )

    def test_sensitive_action_pin_lock_keeps_failed_counter(self):
        self._set_security_param('acpec_mobile_auth.mobile_pin_max_attempts', 2)
        self._set_security_param('acpec_mobile_auth.mobile_pin_lock_seconds', 0)

        user, session = self._trusted_session()
        controller = self._controller_for_session(session)

        self._expect_access_error_without_savepoint(
            controller._require_sensitive_action_pin,
            {'action_code': '9999'},
            purpose='wrong_pin_1',
        )
        user.invalidate_recordset(['mobile_pin_failed_count', 'mobile_pin_locked_until'])
        self.assertEqual(user.mobile_pin_failed_count, 1)
        self.assertFalse(user.mobile_pin_locked_until)

        self._expect_access_error_without_savepoint(
            controller._require_sensitive_action_pin,
            {'action_code': '9999'},
            purpose='wrong_pin_2',
        )
        user.invalidate_recordset(['mobile_pin_failed_count', 'mobile_pin_locked_until'])
        self.assertEqual(user.mobile_pin_failed_count, 2)
        self.assertTrue(user.mobile_pin_locked_until)

    def test_sensitive_action_pin_hard_block_requires_pin_reset(self):
        self._set_security_param('acpec_mobile_auth.mobile_pin_max_attempts', 2)
        self._set_security_param('acpec_mobile_auth.mobile_pin_lock_seconds', 30)
        self._set_security_param('acpec_mobile_auth.mobile_pin_hard_block_attempts', 10)

        user, session = self._trusted_session()
        controller = self._controller_for_session(session)

        for attempt in range(1, 10):
            self._expect_access_error_without_savepoint(
                controller._require_sensitive_action_pin,
                {'action_code': '9999'},
                purpose='wrong_pin_%s' % attempt,
            )
            user.sudo().write({'mobile_pin_locked_until': False})

        self._expect_access_error_without_savepoint(
            controller._require_sensitive_action_pin,
            {'action_code': '9999'},
            purpose='wrong_pin_hard_block',
        )

        user.invalidate_recordset([
            'mobile_pin_failed_count',
            'mobile_pin_required',
            'mobile_pin_set',
            'mobile_pin_hash',
            'mobile_pin_salt',
            'mobile_pin_locked_until',
        ])
        self.assertEqual(user.mobile_pin_failed_count, 10)
        self.assertTrue(user.mobile_pin_required)
        self.assertFalse(user.mobile_pin_set)
        self.assertFalse(user.mobile_pin_hash)
        self.assertFalse(user.mobile_pin_salt)
        self.assertFalse(user.mobile_pin_locked_until)


    def test_sensitive_action_pin_is_not_a_substitute_for_trusted_device(self):
        user = self._create_mobile_user('pending-device-pin-21a@example.com')
        token_data = self.env['acpec.mobile.session'].sudo().create_for_user(user, {
            'device_uid': 'pending-device-pin-21a',
            'platform': 'android',
        })
        session = token_data['session']
        controller = self._controller_for_session(session)

        with self.assertRaises(AccessError):
            controller._require_sensitive_action_pin(
                {'action_code': '1234'},
                purpose='pending_device',
            )

    def test_sensitive_action_pin_rejects_legacy_pin_aliases(self):
        controller = AcpecMobileAuthApiCommon()
        for key in ('action_pin', 'pin', 'secret_code'):
            with self.assertRaises(ValidationError):
                controller._get_sensitive_action_pin({key: '1234'})

        with self.assertRaises(ValidationError):
            controller._get_sensitive_action_pin({
                'action_code': '1234',
                'secret_code': '1234',
            })
