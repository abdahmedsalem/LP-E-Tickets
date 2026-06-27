# -*- coding: utf-8 -*-
from odoo import _, fields, models
from odoo.exceptions import UserError


class AcpecFuelTokenMobilePhoneChangeWizard(models.TransientModel):
    _name = 'acpec.fueltoken.mobile.phone.change.wizard'
    _description = 'Assistant de changement de téléphone mobile FuelToken'

    user_id = fields.Many2one('res.users', string='Utilisateur mobile', required=True)
    old_phone = fields.Char(string='Ancien téléphone', readonly=True)
    new_phone = fields.Char(string='Nouveau téléphone', required=True)
    reason = fields.Text(string='Motif', required=True)

    def default_get(self, fields_list):
        vals = super().default_get(fields_list)
        user = self.env['res.users'].browse(vals.get('user_id') or self.env.context.get('default_user_id')).exists()
        if user:
            vals.setdefault('user_id', user.id)
            vals.setdefault('old_phone', user.mobile_phone or False)
        return vals

    def action_apply(self):
        self.ensure_one()
        if not self.reason or not self.reason.strip():
            raise UserError(_('Le motif du changement de téléphone est obligatoire.'))
        self.user_id.action_fueltoken_change_mobile_phone(
            self.new_phone,
            self.reason,
            source='backoffice',
        )
        return {'type': 'ir.actions.act_window_close'}
