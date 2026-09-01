from odoo import models, fields, api, _

class AcpecFuelPurchaseProofWizard(models.TransientModel):
    _name = 'acpec.fuel.purchase.proof.wizard'
    _description = 'Prévisualisation de la preuve de paiement'

    purchase_id = fields.Many2one(
        'acpec.fuel.purchase',
        string='Achat',
        required=True,
        ondelete='cascade',
    )
    attachment_id = fields.Many2one('ir.attachment', string='Pièce jointe')
    proof_image = fields.Binary(
        related='attachment_id.datas',
        string='Preuve de paiement',
        readonly=True,
    )
    filename = fields.Char(
        related='attachment_id.name',
        string='Nom du fichier',
        readonly=True,
    )

    def action_download(self):
        self.ensure_one()
        if not self.attachment_id:
            return {'type': 'ir.actions.act_window_close'}
        return {
            'type': 'ir.actions.act_url',
            'url': '/web/content/%s?download=true' % self.attachment_id.id,
            'target': 'self',
        }
