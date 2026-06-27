# -*- coding: utf-8 -*-
from odoo import _, api, fields, models
from odoo.exceptions import UserError


class AcpecFuelTokenMobileUserStateWizard(models.TransientModel):
    _name = 'acpec.fueltoken.mobile.user.state.wizard'
    _description = 'Confirmation blocage/réactivation utilisateur mobile'

    user_id = fields.Many2one('res.users', required=True, readonly=True)
    operation = fields.Selection([
        ('block', 'Bloquer'),
        ('reactivate', 'Réactiver'),
    ], required=True, readonly=True)
    target_state = fields.Selection([
        ('self_registered', 'Self registered'),
        ('approved', 'Approved'),
    ], default='self_registered')
    reason = fields.Text(required=True)
    warning_message = fields.Text(compute='_compute_warning_message', readonly=True)

    @api.depends('operation', 'user_id', 'target_state')
    def _compute_warning_message(self):
        for wizard in self:
            if wizard.operation == 'block':
                wizard.warning_message = _(
                    "Attention : cette action bloque l'utilisateur mobile. "
                    "Les OTP/login seront refusés et les sessions actives seront révoquées. "
                    "Les devices ne seront pas modifiés automatiquement."
                )
            elif wizard.operation == 'reactivate':
                wizard.warning_message = _(
                    "Attention : cette action réactive l'utilisateur mobile. "
                    "Aucune session ne sera restaurée et aucun device ne sera approuvé automatiquement."
                )
            else:
                wizard.warning_message = False

    def action_confirm(self):
        self.ensure_one()
        reason = (self.reason or '').strip()
        if not reason:
            raise UserError(_("Le motif est obligatoire."))

        if self.operation == 'block':
            self.user_id.action_fueltoken_block_mobile_user(
                reason,
                source='backoffice_wizard',
            )
        elif self.operation == 'reactivate':
            self.user_id.action_fueltoken_reactivate_mobile_user(
                reason,
                target_state=self.target_state or 'self_registered',
                source='backoffice_wizard',
            )
        else:
            raise UserError(_("Opération non supportée."))

        return {'type': 'ir.actions.act_window_close'}
