from odoo.exceptions import AccessError
from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestMobileSecuritySettingBackoffice(TransactionCase):

    def setUp(self):
        super().setUp()
        self.settings = self.env['acpec.mobile.security.setting'].sudo()
        self.group_admin = self.env.ref('acpec_mobile_auth.group_mobile_auth_admin')
        self.internal_group = self.env.ref('base.group_user')

        self.admin_user = self.env['res.users'].with_context(no_reset_password=True).create({
            'name': 'Administrateur sécurité mobile',
            'login': 'mobile.security.admin@example.com',
            'email': 'mobile.security.admin@example.com',
            'group_ids': [(6, 0, [self.internal_group.id, self.group_admin.id])],
        })
        self.regular_user = self.env['res.users'].with_context(no_reset_password=True).create({
            'name': 'Utilisateur interne standard',
            'login': 'regular.security.user@example.com',
            'email': 'regular.security.user@example.com',
            'group_ids': [(6, 0, [self.internal_group.id])],
        })

    def _clear_setting(self, key):
        self.settings.search([('key', '=', key)]).unlink()

    def test_mobile_security_setting_menu_and_action_exist(self):
        action = self.env.ref('acpec_mobile_auth.action_acpec_mobile_security_setting')
        menu = self.env.ref('acpec_mobile_auth.menu_mobile_auth_security_settings')

        self.assertEqual(action.name, 'Paramètres de sécurité mobile')
        self.assertEqual(action.res_model, 'acpec.mobile.security.setting')
        self.assertEqual(action.view_mode, 'list,form')
        self.assertEqual(menu.name, 'Paramètres de sécurité')
        self.assertEqual(menu.parent_id, self.env.ref('acpec_mobile_auth.menu_mobile_auth_configuration'))
        self.assertIn(self.group_admin, menu.group_ids)

    def test_mobile_security_setting_views_expose_expected_fields(self):
        tree_arch = self.env.ref('acpec_mobile_auth.view_acpec_mobile_security_setting_tree').arch_db
        form_arch = self.env.ref('acpec_mobile_auth.view_acpec_mobile_security_setting_form').arch_db
        search_arch = self.env.ref('acpec_mobile_auth.view_acpec_mobile_security_setting_search').arch_db
        action = self.env.ref('acpec_mobile_auth.action_acpec_mobile_security_setting')

        for field_name in ['key', 'value', 'active']:
            self.assertIn(field_name, tree_arch)
            self.assertIn(field_name, form_arch)

        self.assertIn('Paramètres de sécurité mobile', tree_arch)
        self.assertIn('Paramètre de sécurité mobile', form_arch)
        self.assertIn('write_uid', tree_arch)
        self.assertIn('write_date', tree_arch)
        self.assertIn('note', form_arch)
        self.assertIn('Les secrets SMS ne sont volontairement pas gérés ici', action.help)
        self.assertIn('group_by_active', search_arch)
        self.assertIn('Regrouper par actif', search_arch)

    def test_mobile_security_admin_can_manage_setting(self):
        key = 'acpec_mobile_auth.access_token_minutes'
        self._clear_setting(key)

        record = self.env['acpec.mobile.security.setting'].with_user(self.admin_user).create({
            'key': key,
            'value': '20',
            'active': True,
            'note': 'Test administrateur back-office',
        })

        self.assertEqual(record.value, '20')

        record.with_user(self.admin_user).write({'value': '25'})
        record.invalidate_recordset(['value'])
        self.assertEqual(record.value, '25')

    def test_regular_internal_user_cannot_manage_setting(self):
        key = 'acpec_mobile_auth.refresh_token_days'
        self._clear_setting(key)

        setting_model = self.env['acpec.mobile.security.setting'].with_user(self.regular_user)

        with self.assertRaises(AccessError):
            setting_model.create({
                'key': key,
                'value': '20',
                'active': True,
            })
