# -*- coding: utf-8 -*-
from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_mobile_auth.controllers.api_session import AcpecMobileAuthApiSession


def _acpec_test_mobile_phone(label):
    """Return a deterministic canonical 8-digit mobile phone for test labels."""
    value = 2166136261
    for char in str(label):
        value ^= ord(char)
        value = (value * 16777619) % 10000000
    return "3%07d" % value


@tagged('post_install', '-at_install')
class TestConfirmPinEndpoint(TransactionCase):

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

    def _create_mobile_user(self, login='confirm-pin@example.com'):
        user_model = self.env['res.users'].sudo().with_context(
            acpec_mobile_allow_password_write=True,
            no_reset_password=True,
        )
        user = user_model.create({
            'name': login,
            'login': _acpec_test_mobile_phone(login),
            'mobile_phone': _acpec_test_mobile_phone(login),
            'email': login,
            'active': True,
            'mobile_only': True,
            'mobile_state': 'approved',
            'password': user_model._acpec_mobile_unusable_password(),
            'group_ids': [(6, 0, self._group_ids())],
        })
        user.set_mobile_pin('1234')
        return user

    def _session(self, suffix='trusted', trusted=True):
        user = self._create_mobile_user('confirm-pin-%s@example.com' % suffix)
        token_data = self.env['acpec.mobile.session'].sudo().create_for_user(user, {
            'device_uid': 'confirm-pin-device-%s' % suffix,
            'platform': 'android',
        })
        session = token_data['session']
        if trusted:
            session.action_trust_device()
        return user, session

    def _controller(self, session):
        controller = AcpecMobileAuthApiSession()
        controller._test_env = self.env
        controller._get_mobile_session = lambda required=True: session
        return controller

    def _set_security_param(self, key, value):
        settings = self.env['acpec.mobile.security.setting'].sudo()
        settings.search([('key', '=', key)]).unlink()
        settings.create({
            'key': key,
            'value': str(value),
            'active': True,
        })

    def _error_code(self, response):
        self.assertFalse(response['ok'])
        self.assertFalse(response['success'])
        self.assertIn('reference', response['error'])
        self.assertTrue(str(response['error']['reference']).startswith('SEC-'))
        return response['error']['code']

    def test_confirm_pin_accepts_correct_pin_on_trusted_device(self):
        user, session = self._session('success', trusted=True)
        response = self._controller(session).confirm_pin(action_code='1234')

        self.assertTrue(response['ok'])
        self.assertTrue(response['success'])
        self.assertTrue(response['data']['unlocked'])

    def test_confirm_pin_rejects_wrong_pin_with_distinct_public_code(self):
        user, session = self._session('wrong-pin', trusted=True)
        response = self._controller(session).confirm_pin(action_code='9999')

        self.assertEqual(self._error_code(response), 'INVALID_ACTION_CODE')
        user.invalidate_recordset(['mobile_pin_failed_count'])
        self.assertEqual(user.mobile_pin_failed_count, 1)

    def test_confirm_pin_exposes_action_code_locked(self):
        self._set_security_param('acpec_mobile_auth.mobile_pin_max_attempts', 1)
        self._set_security_param('acpec_mobile_auth.mobile_pin_lock_seconds', 30)

        user, session = self._session('locked', trusted=True)
        response = self._controller(session).confirm_pin(action_code='9999')

        self.assertEqual(self._error_code(response), 'ACTION_CODE_LOCKED')

    def test_confirm_pin_exposes_pin_reset_required_on_hard_block(self):
        # The policy clamps mobile_pin_hard_block_attempts to a minimum of 10.
        # Keep max_attempts at the same threshold so the test reaches the
        # hard-block before a temporary lockout stops further attempts.
        self._set_security_param('acpec_mobile_auth.mobile_pin_max_attempts', 10)
        self._set_security_param('acpec_mobile_auth.mobile_pin_lock_seconds', 30)
        self._set_security_param('acpec_mobile_auth.mobile_pin_hard_block_attempts', 10)

        user, session = self._session('hard-block', trusted=True)
        controller = self._controller(session)

        response = False
        for attempt in range(10):
            response = controller.confirm_pin(action_code='9999')
            if attempt < 9:
                self.assertEqual(self._error_code(response), 'INVALID_ACTION_CODE')

        self.assertEqual(self._error_code(response), 'PIN_RESET_REQUIRED')
        user.invalidate_recordset([
            'mobile_pin_required',
            'mobile_pin_set',
            'mobile_pin_hash',
            'mobile_pin_salt',
        ])
        self.assertTrue(user.mobile_pin_required)
        self.assertFalse(user.mobile_pin_set)
        self.assertFalse(user.mobile_pin_hash)
        self.assertFalse(user.mobile_pin_salt)

    def test_confirm_pin_exposes_pending_device_without_touching_pin_counter(self):
        user, session = self._session('pending', trusted=False)
        response = self._controller(session).confirm_pin(action_code='1234')

        self.assertEqual(self._error_code(response), 'DEVICE_PENDING_TRUST')
        user.invalidate_recordset(['mobile_pin_failed_count'])
        self.assertEqual(user.mobile_pin_failed_count, 0)

    def test_confirm_pin_exposes_blocked_device(self):
        user, session = self._session('blocked', trusted=True)
        session.action_block_device()
        session.invalidate_recordset(['device_trust_state'])

        response = self._controller(session).confirm_pin(action_code='1234')

        self.assertEqual(self._error_code(response), 'DEVICE_BLOCKED')

    def test_confirm_pin_rejects_legacy_pin_aliases_with_distinct_public_code(self):
        user, session = self._session('alias', trusted=True)
        controller = self._controller(session)

        for key in ('pin', 'secret_code', 'action_pin'):
            response = controller.confirm_pin(**{key: '1234'})
            self.assertEqual(self._error_code(response), 'INVALID_ACTION_CODE_KEY')

    def test_confirm_pin_requires_action_code_with_distinct_public_code(self):
        user, session = self._session('missing', trusted=True)
        response = self._controller(session).confirm_pin()

        self.assertEqual(self._error_code(response), 'MISSING_ACTION_CODE')
