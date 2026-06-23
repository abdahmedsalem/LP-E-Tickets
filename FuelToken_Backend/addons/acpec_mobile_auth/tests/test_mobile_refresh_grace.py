# -*- coding: utf-8 -*-
from dateutil.relativedelta import relativedelta

from odoo import fields
from odoo.exceptions import AccessError
from odoo.tests.common import TransactionCase, tagged


@tagged("post_install", "-at_install")
class TestMobileRefreshGrace(TransactionCase):

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

    def _create_mobile_user(self, login):
        user_model = self.env['res.users'].sudo().with_context(
            acpec_mobile_allow_password_write=True,
            no_reset_password=True,
        )
        return user_model.create({
            'name': login,
            'login': login,
            'email': login,
            'active': True,
            'mobile_only': True,
            'mobile_state': 'approved',
            'password': user_model._acpec_mobile_unusable_password(),
            'group_ids': [(6, 0, self._group_ids())],
        })

    def _set_grace_seconds(self, seconds):
        settings = self.env['acpec.mobile.security.setting'].sudo()
        key = 'acpec_mobile_auth.refresh_token_grace_seconds'
        settings.search([('key', '=', key)]).unlink()
        settings.create({
            'key': key,
            'value': str(seconds),
            'active': True,
        })

    def test_refresh_token_retry_is_allowed_once_during_grace(self):
        self._set_grace_seconds(30)
        user = self._create_mobile_user('refresh-grace-once-19b@example.com')
        first = self.env['acpec.mobile.session'].sudo().create_for_user(user, {
            'device_uid': 'device-19b',
            'platform': 'android',
        })
        old_session = first['session']
        old_refresh_token = first['refresh_token']

        second = self.env['acpec.mobile.session'].sudo().refresh_with_token(old_refresh_token)
        old_session.invalidate_recordset([
            'state',
            'rotated_at',
            'refresh_grace_until',
            'refresh_grace_used_at',
            'rotated_to_session_id',
        ])

        self.assertEqual(old_session.state, 'rotated')
        self.assertTrue(old_session.rotated_at)
        self.assertTrue(old_session.refresh_grace_until)
        self.assertFalse(old_session.refresh_grace_used_at)
        self.assertEqual(old_session.rotated_to_session_id, second['session'])
        self.assertEqual(second['session'].state, 'active')
        self.assertNotEqual(second['session'], old_session)

        retry = self.env['acpec.mobile.session'].sudo().refresh_with_token(old_refresh_token)
        old_session.invalidate_recordset(['refresh_grace_used_at'])
        self.assertTrue(old_session.refresh_grace_used_at)
        self.assertEqual(retry['session'].state, 'active')
        self.assertNotEqual(retry['session'], old_session)
        self.assertNotEqual(retry['session'], second['session'])

        self.assertTrue(
            self.env['acpec.mobile.session'].sudo().authenticate_access_token(second['access_token'])
        )
        self.assertTrue(
            self.env['acpec.mobile.session'].sudo().authenticate_access_token(retry['access_token'])
        )

        with self.assertRaises(AccessError):
            self.env['acpec.mobile.session'].sudo().refresh_with_token(old_refresh_token)

    def test_refresh_token_retry_is_rejected_after_grace_deadline(self):
        self._set_grace_seconds(30)
        user = self._create_mobile_user('refresh-grace-expired-19b@example.com')
        first = self.env['acpec.mobile.session'].sudo().create_for_user(user)
        old_session = first['session']
        old_refresh_token = first['refresh_token']

        self.env['acpec.mobile.session'].sudo().refresh_with_token(old_refresh_token)
        old_session.sudo().write({
            'refresh_grace_until': fields.Datetime.now() - relativedelta(seconds=1),
        })

        with self.assertRaises(AccessError):
            self.env['acpec.mobile.session'].sudo().refresh_with_token(old_refresh_token)

    def test_refresh_token_grace_can_be_disabled(self):
        self._set_grace_seconds(0)
        user = self._create_mobile_user('refresh-grace-disabled-19b@example.com')
        first = self.env['acpec.mobile.session'].sudo().create_for_user(user)
        old_refresh_token = first['refresh_token']

        self.env['acpec.mobile.session'].sudo().refresh_with_token(old_refresh_token)

        with self.assertRaises(AccessError):
            self.env['acpec.mobile.session'].sudo().refresh_with_token(old_refresh_token)

    def test_refresh_token_grace_seconds_is_bounded(self):
        session_model = self.env['acpec.mobile.session'].sudo()

        self._set_grace_seconds(-1)
        self.assertEqual(session_model._refresh_token_grace_seconds(), 0)

        self._set_grace_seconds(999)
        self.assertEqual(session_model._refresh_token_grace_seconds(), 120)

        self._set_grace_seconds('invalid')
        self.assertEqual(session_model._refresh_token_grace_seconds(), 30)
