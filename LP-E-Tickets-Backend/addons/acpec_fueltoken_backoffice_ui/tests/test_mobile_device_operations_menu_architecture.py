# -*- coding: utf-8 -*-
from odoo.tests.common import TransactionCase, tagged
from odoo.tools.safe_eval import safe_eval


@tagged('post_install', '-at_install')
class TestMobileDeviceOperationsMenuArchitecture(TransactionCase):

    def _domain(self, action):
        return safe_eval(action.domain or '[]')

    def _context(self, action):
        return safe_eval(action.context or '{}')

    def test_patch43m0_mobile_auth_roots_stay_hidden(self):
        root = self.env.ref('acpec_mobile_auth.menu_mobile_auth_root')
        operations = self.env.ref('acpec_mobile_auth.menu_mobile_auth_operations')
        configuration = self.env.ref('acpec_mobile_auth.menu_mobile_auth_configuration')

        self.assertFalse(root.active)
        self.assertFalse(operations.active)
        self.assertFalse(configuration.active)

    def test_patch43m0_devices_to_approve_is_daily_operation_on_device_model(self):
        menu = self.env.ref('acpec_fueltoken_backoffice_ui.menu_today_mobile_devices_to_approve')
        action = self.env.ref('acpec_fueltoken_backoffice_ui.action_today_mobile_devices_to_approve')
        operations = self.env.ref('acpec_fueltoken_base.menu_acpec_fueltoken_operations')
        mobile_admin = self.env.ref('acpec_mobile_auth.group_mobile_auth_admin')

        self.assertEqual(menu.parent_id, operations)
        self.assertEqual(menu.action, action)
        self.assertIn(mobile_admin, menu.group_ids)
        self.assertEqual(action.name, 'Devices à approuver')
        self.assertEqual(action.res_model, 'acpec.mobile.device')

        domain = self._domain(action)
        self.assertIn(('trust_state', '=', 'pending_trust'), domain)
        self.assertIn(('active', '=', True), domain)

        context = self._context(action)
        self.assertEqual(context.get('search_default_pending_trust'), 1)
        self.assertEqual(context.get('search_default_active'), 1)
        self.assertEqual(context.get('search_default_group_by_user'), 1)
        self.assertFalse(context.get('create'))
        self.assertFalse(context.get('delete'))

    def test_patch43m0_sessions_device_attention_is_daily_operation_on_session_model(self):
        menu = self.env.ref('acpec_fueltoken_backoffice_ui.menu_today_mobile_sessions_device_attention')
        action = self.env.ref('acpec_fueltoken_backoffice_ui.action_today_mobile_sessions_device_attention')
        operations = self.env.ref('acpec_fueltoken_base.menu_acpec_fueltoken_operations')
        mobile_admin = self.env.ref('acpec_mobile_auth.group_mobile_auth_admin')

        self.assertEqual(menu.parent_id, operations)
        self.assertEqual(menu.action, action)
        self.assertIn(mobile_admin, menu.group_ids)
        self.assertEqual(action.name, 'Sessions devices à traiter')
        self.assertEqual(action.res_model, 'acpec.mobile.session')

        domain = self._domain(action)
        self.assertIn(('user_id.acpec_mobile_only', '=', True), domain)
        self.assertIn(('device_uid', '!=', False), domain)
        self.assertIn(('device_uid', '!=', ''), domain)
        self.assertIn(('is_device_approval_candidate', '=', True), domain)
        self.assertIn(('device_trust_state', '=', 'pending_trust'), domain)
        self.assertIn(('device_trust_state', '=', 'blocked'), domain)
        self.assertIn(('state', '=', 'active'), domain)
        self.assertIn(('state', 'in', ['active', 'revoked']), domain)

        context = self._context(action)
        self.assertEqual(context.get('search_default_approval_candidate'), 1)
        self.assertEqual(context.get('search_default_pending_trust'), 1)
        self.assertEqual(context.get('search_default_group_by_mobile_user_label'), 1)
        self.assertFalse(context.get('create'))
        self.assertFalse(context.get('delete'))

    def test_patch43m0_old_misleading_config_shortcut_is_disabled(self):
        menu = self.env.ref('acpec_fueltoken_backoffice_ui.menu_backoffice_mobile_devices_to_approve')

        self.assertFalse(menu.active)

    def test_patch43m0_audit_menus_stay_in_configuration(self):
        config = self.env.ref('acpec_fueltoken_base.menu_acpec_fueltoken_config')

        devices_menu = self.env.ref('acpec_fueltoken_backoffice_ui.menu_backoffice_mobile_devices_all')
        devices_action = self.env.ref('acpec_mobile_auth.action_acpec_mobile_device')
        self.assertEqual(devices_menu.parent_id, config)
        self.assertEqual(devices_menu.action, devices_action)
        self.assertEqual(devices_action.res_model, 'acpec.mobile.device')

        sessions_menu = self.env.ref('acpec_mobile_auth.menu_mobile_auth_sessions')
        sessions_action = self.env.ref('acpec_mobile_auth.action_acpec_mobile_session')
        self.assertEqual(sessions_menu.parent_id, config)
        self.assertEqual(sessions_menu.action, sessions_action)
        self.assertEqual(sessions_action.res_model, 'acpec.mobile.session')
