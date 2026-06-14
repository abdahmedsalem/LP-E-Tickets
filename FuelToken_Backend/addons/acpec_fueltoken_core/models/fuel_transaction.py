from odoo import api, fields, models, _
from odoo.exceptions import UserError


class AcpecFuelTransaction(models.Model):
    _name = 'acpec.fuel.transaction'
    _description = 'Transaction Tickets Carburant'
    _order = 'id desc'

    name = fields.Char(string='Référence', default='New', readonly=True, copy=False)
    transaction_type = fields.Selection([
        ('achat_carnets', 'Achat de carnets'),
        ('emission_qr', 'Émission QR'),
        ('retirer_qr', 'Retrait partiel QR'),
        ('separer_qr', 'Separation QR expire/non expire'),
        ('blocage_qr', 'Blocage QR'),
        ('consommation_station', 'Consommation station'),
        ('expiration_faces', 'Expiration faces'),
        ('expiration_qr', 'Expiration QR'),
        ('transfert_carnet', 'Transfert de carnets'),
    ], string='Type', required=True, index=True)
    wallet_id = fields.Many2one('acpec.fuel.wallet', string='Compte Tickets Carburant', index=True)
    partner_id = fields.Many2one('res.partner', related='wallet_id.partner_id', store=True, readonly=True, index=True)
    company_id = fields.Many2one('res.company', string='Société', required=True, default=lambda self: self.env.company, index=True)
    currency_id = fields.Many2one('res.currency', related='company_id.currency_id', store=True, readonly=True)
    purchase_id = fields.Many2one('acpec.fuel.purchase', string='Lot d’achat', index=True)
    purchase_state = fields.Selection(
        related='purchase_id.state',
        store=True,
        readonly=True,
    )
    purchase_submitted_at = fields.Datetime(
        related='purchase_id.submitted_at',
        store=True,
        readonly=True,
    )
    purchase_approved_at = fields.Datetime(
        related='purchase_id.approved_at',
        store=True,
        readonly=True,
    )
    purchase_rejected_at = fields.Datetime(
        related='purchase_id.rejected_at',
        store=True,
        readonly=True,
    )
    purchase_rejection_reason = fields.Text(
        related='purchase_id.rejection_reason',
        store=True,
        readonly=True,
    )
    qr_id = fields.Many2one('acpec.fuel.qr', string='QR', index=True)
    parent_qr_id = fields.Many2one('acpec.fuel.qr', string='QR parent', index=True)
    station_id = fields.Many2one('acpec.fuel.station', string='Station', index=True)
    transfer_id = fields.Many2one('acpec.fuel.carnet.transfer', string='Transfert', index=True)
    idempotency_key = fields.Char(string='Clé idempotence', index=True, copy=False)
    line_ids = fields.One2many('acpec.fuel.transaction.line', 'transaction_id', string='Lignes')
    amount_total = fields.Monetary(string='Montant', compute='_compute_totals', store=True)
    qty_total = fields.Integer(string='Quantité', compute='_compute_totals', store=True)
    note = fields.Text(string='Note')

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if vals.get('name', 'New') == 'New':
                vals['name'] = self.env['ir.sequence'].next_by_code('acpec.fuel.transaction') or 'New'
        return super().create(vals_list)

    @api.depends('line_ids.amount', 'line_ids.qty')
    def _compute_totals(self):
        for rec in self:
            rec.amount_total = sum(rec.line_ids.mapped('amount'))
            rec.qty_total = sum(rec.line_ids.mapped('qty'))

    @api.model
    def log(self, transaction_type, company, wallet=False, purchase=False, qr=False, parent_qr=False, station=False, transfer=False, lines=False, note=False, idempotency_key=False):
        vals = {
            'transaction_type': transaction_type,
            'company_id': company.id,
            'wallet_id': wallet.id if wallet else False,
            'purchase_id': purchase.id if purchase else False,
            'qr_id': qr.id if qr else False,
            'parent_qr_id': parent_qr.id if parent_qr else False,
            'station_id': station.id if station else False,
            'transfer_id': transfer.id if transfer else False,
            'note': note or False,
            'idempotency_key': idempotency_key or False,
        }
        tx = self.sudo().create(vals)
        for line in lines or []:
            self.env['acpec.fuel.transaction.line'].sudo().create(dict(line, transaction_id=tx.id))
        return tx

    def write(self, vals):
        if not self.env.context.get('allow_fuel_transaction_update') and set(vals) - {'note'}:
            raise UserError(_('Les transactions Tickets Carburant ne doivent pas être modifiées directement.'))
        return super().write(vals)


class AcpecFuelTransactionLine(models.Model):
    _name = 'acpec.fuel.transaction.line'
    _description = 'Ligne transaction Tickets Carburant'
    _order = 'transaction_id, id'

    transaction_id = fields.Many2one('acpec.fuel.transaction', string='Transaction', required=True, ondelete='cascade')
    company_id = fields.Many2one('res.company', related='transaction_id.company_id', store=True, readonly=True)
    currency_id = fields.Many2one('res.currency', related='transaction_id.currency_id', store=True, readonly=True)
    purchase_id = fields.Many2one('acpec.fuel.purchase', string='Lot d’achat', index=True)
    purchase_line_id = fields.Many2one('acpec.fuel.purchase.line', string='Ligne d’achat', index=True)
    face_line_id = fields.Many2one('acpec.fuel.face.line', string='Ligne de faces', index=True)
    qr_id = fields.Many2one('acpec.fuel.qr', string='QR', index=True)
    qr_line_id = fields.Many2one('acpec.fuel.qr.line', string='Ligne QR', index=True)
    transfer_id = fields.Many2one('acpec.fuel.carnet.transfer', string='Transfert', index=True)
    face_value = fields.Monetary(string='Valeur de face', required=True)
    qty = fields.Integer(string='Quantité', required=True)
    amount = fields.Monetary(string='Montant', compute='_compute_amount', store=True)

    @api.depends('face_value', 'qty')
    def _compute_amount(self):
        for rec in self:
            rec.amount = rec.face_value * rec.qty
