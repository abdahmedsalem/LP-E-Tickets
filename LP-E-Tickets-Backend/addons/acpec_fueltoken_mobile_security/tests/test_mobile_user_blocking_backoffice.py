# -*- coding: utf-8 -*-
from odoo.exceptions import UserError
from odoo.tests.common import TransactionCase, tagged


def _acpec_test_mobile_phone(label):
    value = 2166136261
    for char in str(label):
        value ^= ord(char)
        value = (value * 16777619) % 10000000
    return "3%07d" % value


@tagged('post_install', '-at_install')
class TestMobileUserBlockingBackofficeLifecycle(TransactionCase):

    def setUp(self):
        super().setUp()
        group = self.env.ref('acpec_mobile_auth.group_mobile_auth_admin', raise_if_not_found=False)
        if group:
            self.env.user.sudo().write({'group_ids': [(4, group.id)]})

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

    def _create_mobile_user(self, label, state='self_registered'):
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
            'acpec_mobile_only': True,
            'acpec_mobile_state': state,
            'password': Users._acpec_mobile_unusable_password(),
            'group_ids': [(6, 0, self._group_ids())],
        })

    def _create_session(self, user, device_uid):
        return self.env['acpec.mobile.session'].sudo().create_for_user(user, {
            'device_uid': device_uid,
            'device_name': device_uid,
            'platform': 'android',
            'app_version': 'test-f2l',
        })['session']

    def _assert_partner_chatter_contains(self, partner, text):
        count = self.env['mail.message'].sudo().search_count([
            ('model', '=', 'res.partner'),
            ('res_id', '=', partner.id),
            ('body', 'ilike', text),
        ])
        self.assertGreater(count, 0)

    def test_f2l_block_mobile_user_from_bo_posts_chatter_and_preserves_devices(self):
        user = self._create_mobile_user(
            'f2l-block-user-backoffice',
            state='self_registered',
        )
        partner = user.partner_id

        trusted_session = self._create_session(user, 'ft-f2l-block-trusted-device')
        trusted_device = trusted_session.device_id
        trusted_device.action_trust_device()

        pending_session = self._create_session(user, 'ft-f2l-block-pending-device')
        pending_device = pending_session.device_id

        blocked_session = self._create_session(user, 'ft-f2l-block-blocked-device')
        blocked_device = blocked_session.device_id
        blocked_device.action_block_device()

        reason = 'F2L blocage BO test motif obligatoire'
        result = user.action_fueltoken_block_mobile_user(reason, source='backoffice_test')

        self.assertTrue(result)

        user.invalidate_recordset(['acpec_mobile_state', 'active'])
        trusted_session.invalidate_recordset(['state', 'revoked_at'])
        pending_session.invalidate_recordset(['state', 'revoked_at'])
        blocked_session.invalidate_recordset(['state', 'revoked_at'])
        trusted_device.invalidate_recordset(['trust_state', 'trusted_at', 'blocked_at'])
        pending_device.invalidate_recordset(['trust_state', 'trusted_at', 'blocked_at'])
        blocked_device.invalidate_recordset(['trust_state', 'trusted_at', 'blocked_at'])

        self.assertTrue(user.active)
        self.assertEqual(user.acpec_mobile_state, 'blocked')

        self.assertEqual(trusted_session.state, 'revoked')
        self.assertTrue(trusted_session.revoked_at)
        self.assertEqual(pending_session.state, 'revoked')
        self.assertTrue(pending_session.revoked_at)
        self.assertEqual(blocked_session.state, 'revoked')

        self.assertEqual(trusted_device.trust_state, 'trusted')
        self.assertEqual(pending_device.trust_state, 'pending_trust')
        self.assertEqual(blocked_device.trust_state, 'blocked')

        self._assert_partner_chatter_contains(partner, reason)
        self._assert_partner_chatter_contains(partner, 'blocked')

    def test_f2l_reactivate_mobile_user_from_bo_posts_chatter_and_preserves_devices(self):
        user = self._create_mobile_user(
            'f2l-reactivate-user-backoffice',
            state='self_registered',
        )
        partner = user.partner_id

        trusted_session = self._create_session(user, 'ft-f2l-reactivate-trusted-device')
        trusted_device = trusted_session.device_id
        trusted_device.action_trust_device()

        pending_session = self._create_session(user, 'ft-f2l-reactivate-pending-device')
        pending_device = pending_session.device_id

        user.action_fueltoken_block_mobile_user(
            'F2L préalable blocage',
            source='backoffice_test',
        )

        trusted_session.invalidate_recordset(['state'])
        pending_session.invalidate_recordset(['state'])
        trusted_device.invalidate_recordset(['trust_state'])
        pending_device.invalidate_recordset(['trust_state'])

        self.assertEqual(trusted_session.state, 'revoked')
        self.assertEqual(pending_session.state, 'revoked')
        self.assertEqual(trusted_device.trust_state, 'trusted')
        self.assertEqual(pending_device.trust_state, 'pending_trust')

        reason = 'F2L réactivation BO test motif obligatoire'
        result = user.action_fueltoken_reactivate_mobile_user(
            reason,
            target_state='self_registered',
            source='backoffice_test',
        )

        self.assertTrue(result)

        user.invalidate_recordset(['acpec_mobile_state', 'active'])
        trusted_session.invalidate_recordset(['state'])
        pending_session.invalidate_recordset(['state'])
        trusted_device.invalidate_recordset(['trust_state'])
        pending_device.invalidate_recordset(['trust_state'])

        self.assertTrue(user.active)
        self.assertEqual(user.acpec_mobile_state, 'self_registered')

        # Réactivation user : aucune session restaurée, aucun device modifié.
        self.assertEqual(trusted_session.state, 'revoked')
        self.assertEqual(pending_session.state, 'revoked')
        self.assertEqual(trusted_device.trust_state, 'trusted')
        self.assertEqual(pending_device.trust_state, 'pending_trust')

        self._assert_partner_chatter_contains(partner, reason)
        self._assert_partner_chatter_contains(partner, 'self_registered')

    def test_f2l_wizard_requires_reason_and_executes_block_and_reactivate(self):
        user = self._create_mobile_user(
            'f2l-wizard-user-backoffice',
            state='self_registered',
        )
        Wizard = self.env['acpec.fueltoken.mobile.user.state.wizard'].sudo()

        block_wizard = Wizard.create({
            'user_id': user.id,
            'operation': 'block',
            'reason': ' ',
        })

        with self.assertRaises(UserError):
            block_wizard.action_confirm()

        block_reason = 'F2L wizard block reason'
        block_wizard.write({'reason': block_reason})
        action = block_wizard.action_confirm()

        self.assertEqual(action.get('type'), 'ir.actions.act_window_close')

        user.invalidate_recordset(['acpec_mobile_state'])
        self.assertEqual(user.acpec_mobile_state, 'blocked')
        self._assert_partner_chatter_contains(user.partner_id, block_reason)

        reactivate_reason = 'F2L wizard reactivate reason'
        reactivate_wizard = Wizard.create({
            'user_id': user.id,
            'operation': 'reactivate',
            'target_state': 'self_registered',
            'reason': reactivate_reason,
        })
        action = reactivate_wizard.action_confirm()

        self.assertEqual(action.get('type'), 'ir.actions.act_window_close')

        user.invalidate_recordset(['acpec_mobile_state'])
        self.assertEqual(user.acpec_mobile_state, 'self_registered')
        self._assert_partner_chatter_contains(user.partner_id, reactivate_reason)

    def test_f2l_backoffice_views_expose_buttons_and_warning_wizard(self):
        user_view = self.env.ref(
            'acpec_fueltoken_mobile_security.view_users_form_acpec_fueltoken_mobile_user_blocking'
        )
        wizard_view = self.env.ref(
            'acpec_fueltoken_mobile_security.view_acpec_fueltoken_mobile_user_state_wizard_form'
        )

        self.assertIn('action_open_fueltoken_block_mobile_user_wizard', user_view.arch_db)
        self.assertIn('action_open_fueltoken_reactivate_mobile_user_wizard', user_view.arch_db)
        self.assertIn('Bloquer utilisateur mobile', user_view.arch_db)
        self.assertIn('Réactiver utilisateur mobile', user_view.arch_db)

        self.assertIn('warning_message', wizard_view.arch_db)
        self.assertIn('reason', wizard_view.arch_db)
        self.assertIn('action_confirm', wizard_view.arch_db)
