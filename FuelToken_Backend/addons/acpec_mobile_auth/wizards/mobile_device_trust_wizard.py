# -*- coding: utf-8 -*-
from odoo import _, api, fields, models
from odoo.exceptions import UserError


class AcpecMobileDeviceTrustWizard(models.TransientModel):
    _name = 'acpec.mobile.device.trust.wizard'
    _description = 'Confirmation action confiance device mobile'

    device_id = fields.Many2one('acpec.mobile.device', readonly=True)
    session_id = fields.Many2one('acpec.mobile.session', readonly=True)
    operation = fields.Selection([
        ('block', 'Bloquer'),
        ('reset', 'Remettre en attente'),
    ], required=True, readonly=True)
    reason = fields.Text(required=True)
    warning_message = fields.Text(compute='_compute_warning_message', readonly=True)

    @api.depends('operation')
    def _compute_warning_message(self):
        for wizard in self:
            if wizard.operation == 'block':
                wizard.warning_message = _(
                    "Attention : cette action bloque le device mobile. "
                    "Les sessions actives liées à ce device seront révoquées. "
                    "L'utilisateur mobile ne sera pas bloqué automatiquement."
                )
            elif wizard.operation == 'reset':
                wizard.warning_message = _(
                    "Attention : cette action remet le device en attente de confiance. "
                    "Un device bloqué ne sera pas approuvé directement ; il devra être approuvé séparément ensuite."
                )
            else:
                wizard.warning_message = False

    def _target_record(self):
        self.ensure_one()
        if self.session_id:
            return self.session_id
        if self.device_id:
            return self.device_id
        raise UserError(_("Aucun device ou session mobile cible."))

    def action_confirm(self):
        self.ensure_one()
        reason = (self.reason or '').strip()
        if not reason:
            raise UserError(_("Le motif est obligatoire."))

        target = self._target_record()
        if self.operation == 'block':
            target.action_block_device(reason=reason)
        elif self.operation == 'reset':
            target.action_reset_device_trust(reason=reason)
        else:
            raise UserError(_("Opération non supportée."))

        return {'type': 'ir.actions.act_window_close'}
