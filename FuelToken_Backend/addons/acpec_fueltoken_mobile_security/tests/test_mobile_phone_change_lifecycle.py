# -*- coding: utf-8 -*-
from odoo.exceptions import ValidationError
from odoo.tests.common import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestFuelTokenMobilePhoneChangeLifecycle(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.Company = cls.env['res.company'].sudo()
        cls.User = cls.env['res.users'].sudo().with_context(
            acpec_mobile_allow_password_write=True,
            no_reset_password=True,
        )
        cls.Session = cls.env['acpec.mobile.session'].sudo()
        cls.Request = cls.env['acpec.mobile.auth.account.request'].sudo()
        cls.fuel_company = cls.env.company.sudo()
        cls.Company.search([
            ('acpec_fueltoken_enabled', '=', True),
            ('id', '!=', cls.fuel_company.id),
        ]).write({'acpec_fueltoken_enabled': False})
        cls.fuel_company.write({
            'acpec_fueltoken_enabled': True,
            'acpec_mobile_auth_enabled': True,
        })
        cls.mobile_group_ids = cls._group_ids([
            'base.group_portal',
            'acpec_mobile_auth.group_mobile_auth_user',
        ])

    @classmethod
    def _group_ids(cls, xmlids):
        ids = []
        for xmlid in xmlids:
            group = cls.env.ref(xmlid, raise_if_not_found=False)
            if group:
                ids.append(group.id)
        return ids

    def _mobile_user(self, phone):
        user = self.User.create({
            'name': 'F2G Mobile User %s' % phone,
            'login': phone,
            'active': True,
            'company_id': self.fuel_company.id,
            'company_ids': [(6, 0, [self.fuel_company.id])],
            'mobile_phone': phone,
            'mobile_only': True,
            'mobile_state': 'self_registered',
            'password': self.User._acpec_mobile_unusable_password(),
            'group_ids': [(6, 0, self.mobile_group_ids)],
        })
        user.partner_id.sudo().with_context(
            acpec_fueltoken_allow_mobile_partner_identity_sync=True,
        ).write({
            'acpec_is_mobile_partner': True,
            'ref': 'MOB:%s' % phone,
        })
        return user

    def _session_for_user(self, user, suffix):
        return self.Session.create_for_user(user, {
            'device_uid': 'ft-f2g-phone-change-%s' % suffix,
            'device_name': 'Android F2G %s' % suffix,
            'platform': 'android',
            'app_version': 'test',
        })['session']

    def test_f2g_change_phone_updates_user_partner_ref_and_revokes_sessions(self):
        user = self._mobile_user('33003001')
        session = self._session_for_user(user, 'revoke-session')
        session.device_id.action_trust_device()
        device = session.device_id

        log = user.action_fueltoken_change_mobile_phone(
            '33003002',
            'Client changed phone number.',
        )
        user.invalidate_recordset(['login', 'mobile_phone'])
        user.partner_id.invalidate_recordset(['ref'])
        session.invalidate_recordset(['state', 'revoked_at'])
        device.invalidate_recordset(['trust_state'])

        self.assertEqual(user.login, '33003002')
        self.assertEqual(user.mobile_phone, '33003002')
        self.assertEqual(user.partner_id.ref, 'MOB:33003002')
        self.assertEqual(session.state, 'revoked')
        self.assertTrue(session.revoked_at)
        self.assertEqual(device.trust_state, 'trusted')
        self.assertEqual(log.old_phone, '33003001')
        self.assertEqual(log.new_phone, '33003002')
        self.assertTrue(log.revoke_active_sessions)
        self.assertEqual(log.active_sessions_revoked_count, 1)

    def test_f2g_direct_partner_ref_write_is_refused_and_phone_change_resyncs_ref(self):
        user = self._mobile_user('33003003')

        with self.assertRaises(ValidationError):
            user.partner_id.sudo().write({'ref': 'CLIENT-MANUAL-REF'})

        log = user.action_fueltoken_change_mobile_phone(
            '33003004',
            'Client phone change keeps technical mobile ref canonical.',
        )
        user.partner_id.invalidate_recordset(['name', 'ref'])

        self.assertEqual(user.partner_id.name, '33003004 - F2G Mobile User 33003003')
        self.assertEqual(user.partner_id.ref, 'MOB:33003004')
        self.assertEqual(log.old_partner_ref, 'MOB:33003003')
        self.assertEqual(log.new_partner_ref, 'MOB:33003004')

    def test_f2g_change_phone_revokes_all_active_sessions_without_blocking_device(self):
        user = self._mobile_user('33003005')
        first_session = self._session_for_user(user, 'revoke-session-a')
        second_session = self._session_for_user(user, 'revoke-session-b')
        first_session.device_id.action_trust_device()
        device = first_session.device_id

        log = user.action_fueltoken_change_mobile_phone(
            '33003006',
            'Recovery after phone change.',
        )
        first_session.invalidate_recordset(['state', 'revoked_at'])
        second_session.invalidate_recordset(['state', 'revoked_at'])
        device.invalidate_recordset(['trust_state'])

        self.assertEqual(first_session.state, 'revoked')
        self.assertEqual(second_session.state, 'revoked')
        self.assertTrue(first_session.revoked_at)
        self.assertTrue(second_session.revoked_at)
        self.assertEqual(device.trust_state, 'trusted')
        self.assertTrue(log.revoke_active_sessions)
        self.assertEqual(log.active_sessions_revoked_count, 2)

    def test_f2g_direct_write_of_fuel_mobile_identity_is_refused(self):
        user = self._mobile_user('33003007')

        with self.assertRaises(ValidationError):
            user.write({
                'login': '33003008',
                'mobile_phone': '33003008',
            })

        user.invalidate_recordset(['login', 'mobile_phone'])
        self.assertEqual(user.login, '33003007')
        self.assertEqual(user.mobile_phone, '33003007')

    def test_f2g_change_phone_rejects_duplicate_mobile_identity(self):
        user = self._mobile_user('33003009')
        self._mobile_user('33003010')

        with self.assertRaises(ValidationError):
            user.action_fueltoken_change_mobile_phone(
                '33003010',
                'Duplicate phone must be refused.',
            )

    def test_f2g_account_request_approval_can_still_set_initial_mobile_phone(self):
        phone = '33003011'
        user = self.User.create({
            'name': 'F2G Approval User',
            'login': phone,
            'active': True,
            'company_id': self.fuel_company.id,
            'company_ids': [(6, 0, [self.fuel_company.id])],
            'password': self.User._acpec_mobile_unusable_password(),
        })
        request = self.Request.create({
            'name_display': 'F2G Approval User',
            'signup_identifier': phone,
            'signup_identifier_type': 'phone',
            'phone': phone,
            'login': phone,
            'company_id': self.fuel_company.id,
            'user_id': user.id,
            'partner_id': user.partner_id.id,
        })

        request.action_approve()
        user.invalidate_recordset(['mobile_phone', 'mobile_only', 'mobile_state'])

        self.assertTrue(user.mobile_only)
        self.assertEqual(user.mobile_state, 'approved')
        self.assertEqual(user.mobile_phone, phone)
