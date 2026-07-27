from odoo.tests.common import TransactionCase


class TestMobilePhoneChangeActionCleanup(TransactionCase):

    def _user_model(self):
        return self.env['ir.model']._get('res.users')

    def _create_bound_server_action(self, name='Changer le téléphone mobile FuelToken'):
        model = self._user_model()
        vals = {
            'name': name,
            'type': 'ir.actions.server',
            'state': 'code',
            'code': 'action = False',
            'model_id': model.id,
        }
        Action = self.env['ir.actions.server'].sudo()
        if 'binding_model_id' in Action._fields:
            vals['binding_model_id'] = model.id
        if 'binding_type' in Action._fields:
            vals['binding_type'] = 'action'
        return Action.create(vals)

    def _create_bound_window_action(self, name='Changer le téléphone mobile FuelToken'):
        model = self._user_model()
        Action = self.env['ir.actions.act_window'].sudo()
        vals = {
            'name': name,
            'type': 'ir.actions.act_window',
            'res_model': 'res.users',
            'view_mode': 'form',
        }
        if 'binding_model_id' in Action._fields:
            vals['binding_model_id'] = model.id
        if 'binding_type' in Action._fields:
            vals['binding_type'] = 'action'
        return Action.create(vals)

    def test_patch43m9_removes_dangerous_mobile_phone_change_actions(self):
        server_action = self._create_bound_server_action()
        window_action = self._create_bound_window_action()

        self.assertTrue(server_action.exists())
        self.assertTrue(window_action.exists())

        removed = self.env['res.users']._acpec_disable_dangerous_mobile_phone_change_actions()

        self.assertTrue(removed)
        self.assertFalse(server_action.exists())
        self.assertFalse(window_action.exists())

    def test_patch43m9_does_not_remove_unrelated_user_actions(self):
        safe_action = self._create_bound_server_action(name='Privacy Lookup')

        self.env['res.users']._acpec_disable_dangerous_mobile_phone_change_actions()

        self.assertTrue(safe_action.exists())
        safe_action.unlink()

    def test_patch43m9_matching_handles_unaccented_and_english_names(self):
        server_action = self._create_bound_server_action(name='Changer le telephone mobile FuelToken')
        english_action = self._create_bound_window_action(name='Change FuelToken mobile phone')

        self.env['res.users']._acpec_disable_dangerous_mobile_phone_change_actions()

        self.assertFalse(server_action.exists())
        self.assertFalse(english_action.exists())
