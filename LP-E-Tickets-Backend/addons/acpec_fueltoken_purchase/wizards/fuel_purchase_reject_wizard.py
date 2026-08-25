from odoo import fields, models, _
from odoo.exceptions import UserError


class AcpecFuelPurchaseRejectWizard(models.TransientModel):
    _name = 'acpec.fuel.purchase.reject.wizard'
    _description = 'Motif de rejet achat FuelToken'

    purchase_id = fields.Many2one(
        'acpec.fuel.purchase',
        string='Lot achat',
        required=True,
        readonly=True,
    )
    rejection_reason = fields.Text(
        string='Motif de rejet',
        required=True,
    )

    def action_confirm_reject(self):
        self.ensure_one()
        purchase = self.purchase_id.exists()
        if not purchase:
            raise UserError(_('Le lot achat est introuvable.'))
        purchase.action_reject(reason=self.rejection_reason)
        return {'type': 'ir.actions.act_window_close'}
