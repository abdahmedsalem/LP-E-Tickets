# -*- coding: utf-8 -*-
from unittest.mock import patch

from odoo.exceptions import AccessError
from odoo.tests.common import TransactionCase, tagged


def _acpec_test_mobile_phone(label):
    value = 2166136261
    for char in str(label):
        value ^= ord(char)
        value = (value * 16777619) % 10000000
    return "3%07d" % value


@tagged('post_install', '-at_install')
class TestMobileUserBlockedOtp(TransactionCase):

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

    def _create_mobile_user(self, label, state='approved'):
        phone = _acpec_test_mobile_phone(label)
        Users = self.env['res.users'].sudo().with_context(
            acpec_mobile_allow_password_write=True,
            no_reset_password=True,
        )
        return Users.create({
            'name': label,
            'login': phone,
            'mobile_phone': phone,
            'active': True,
            'mobile_only': True,
            'mobile_state': state,
            'password': Users._acpec_mobile_unusable_password(),
            'group_ids': [(6, 0, self._group_ids())],
        })

    def test_f2i_blocked_user_cannot_request_login_otp_even_if_station(self):
        user = self._create_mobile_user(
            'f2i-blocked-request-otp@example.com',
            state='blocked',
        )
        station_group = self.env.ref(
            'acpec_fueltoken_base.group_fuel_station',
            raise_if_not_found=False,
        )
        if station_group:
            user.sudo().write({'group_ids': [(4, station_group.id)]})

        Otp = self.env['acpec.mobile.auth.otp'].sudo()
        before_count = Otp.search_count([
            ('identifier', '=', user.mobile_phone),
            ('purpose', '=', 'login'),
        ])

        with patch(
            'odoo.addons.acpec_mobile_auth_otp.models.mobile_auth_otp.AcpecMobileAuthOtp._send_otp_code',
            return_value=True,
        ):
            with self.assertRaises(AccessError) as ctx:
                Otp.request_otp(user.mobile_phone, purpose='login')

        self.assertIn('bloqué', str(ctx.exception))
        after_count = Otp.search_count([
            ('identifier', '=', user.mobile_phone),
            ('purpose', '=', 'login'),
        ])
        self.assertEqual(after_count, before_count)

    def test_f2i_blocked_user_existing_otp_is_not_consumed_and_opens_no_session(self):
        user = self._create_mobile_user(
            'f2i-blocked-existing-otp@example.com',
            state='approved',
        )
        Otp = self.env['acpec.mobile.auth.otp'].sudo()
        Session = self.env['acpec.mobile.session'].sudo()

        with patch(
            'odoo.addons.acpec_mobile_auth_otp.models.mobile_auth_otp.AcpecMobileAuthOtp._send_otp_code',
            return_value=True,
        ):
            challenge, code = Otp.request_otp(user.mobile_phone, purpose='login')

        user.sudo().write({'mobile_state': 'blocked'})
        before_sessions = Session.search_count([('user_id', '=', user.id)])

        with self.assertRaises(AccessError) as ctx:
            challenge.verify(code)

        self.assertIn('bloqué', str(ctx.exception))
        challenge.invalidate_recordset(['state', 'verified_at', 'attempt_count'])
        self.assertEqual(challenge.state, 'pending')
        self.assertFalse(challenge.verified_at)
        self.assertEqual(challenge.attempt_count, 0)
        after_sessions = Session.search_count([('user_id', '=', user.id)])
        self.assertEqual(after_sessions, before_sessions)
