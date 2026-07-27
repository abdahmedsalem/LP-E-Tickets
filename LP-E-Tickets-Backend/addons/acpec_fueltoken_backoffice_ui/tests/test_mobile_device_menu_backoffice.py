# -*- coding: utf-8 -*-
from odoo.tests.common import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestMobileDeviceBackofficeMenu(TransactionCase):

    def test_f2m_devices_audit_menu_exposes_durable_devices_action(self):
        menu = self.env.ref('acpec_fueltoken_backoffice_ui.menu_backoffice_mobile_devices_all')
        action = self.env.ref('acpec_mobile_auth.action_acpec_mobile_device')

        self.assertEqual(menu.name, 'Devices mobiles — audit')
        self.assertTrue(menu.parent_id)
        self.assertEqual(menu.action, action)
        self.assertEqual(action.name, 'Devices mobiles — audit')
        self.assertEqual(action.res_model, 'acpec.mobile.device')

    def test_f2m_device_form_buttons_are_french(self):
        view = self.env.ref('acpec_fueltoken_backoffice_ui.view_mobile_device_form_french')
        arch = view.arch_db

        self.assertIn('action_trust_device', arch)
        self.assertIn('Approuver le device', arch)
        self.assertIn('action_open_block_device_wizard', arch)
        self.assertIn('Bloquer le device', arch)
        self.assertIn('action_open_reset_device_trust_wizard', arch)
        self.assertIn('Remettre en attente', arch)
