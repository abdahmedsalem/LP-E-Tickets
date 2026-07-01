from odoo import api, fields, models, _
from odoo.exceptions import AccessError, ValidationError, UserError


class AcpecFuelTransaction(models.Model):
    _name = 'acpec.fuel.transaction'
    _description = 'Transaction Tickets Carburant'
    _order = 'id desc'

    name = fields.Char(string='Référence', default='New', readonly=True, copy=False)
    transaction_type = fields.Selection([
        ('purchase_submitted', 'Demande d’achat soumise'),
        ('purchase_approved', 'Achat approuvé'),
        ('emission_qr', 'Émission QR'),
        ('retirer_qr', 'Retrait partiel QR'),
        ('separer_qr', 'Separation QR expire/non expire'),
        ('blocage_qr', 'Blocage QR'),
        ('consommation_station', 'Consommation station'),
        ('expiration_faces', 'Expiration faces'),
        ('expiration_qr', 'Expiration QR'),
        ('transfert_carnet', 'Transfert de carnets'),
        ('transfert_ticket', 'Transfert de tickets'),
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
    transfer_id = fields.Many2one('acpec.fuel.carnet.transfer', string='Transfert carnet', index=True)
    ticket_transfer_id = fields.Many2one('acpec.fuel.ticket.transfer', string='Transfert ticket', index=True)
    idempotency_key = fields.Char(string='Clé idempotence', index=True, copy=False)
    request_hash = fields.Char(string='Hash requête idempotence', index=True, copy=False)
    line_ids = fields.One2many('acpec.fuel.transaction.line', 'transaction_id', string='Lignes')
    amount_total = fields.Monetary(string='Montant', compute='_compute_totals', store=True)
    qty_total = fields.Integer(string='Quantité', compute='_compute_totals', store=True)
    note = fields.Text(string='Note')
    regularization_state = fields.Selection([
        ('pending', 'À régulariser'),
        ('regularized', 'Régularisé'),
    ], string='Régularisation station', index=True, copy=False, readonly=True)
    regularization_reference = fields.Char(string='Référence régularisation station', index=True, copy=False, readonly=True)
    regularization_date = fields.Datetime(string='Date régularisation station', copy=False, readonly=True)
    regularized_by_id = fields.Many2one('res.users', string='Régularisé par', copy=False, readonly=True)


    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if vals.get('name', 'New') == 'New':
                vals['name'] = self.env['ir.sequence'].next_by_code('acpec.fuel.transaction') or 'New'
            if vals.get('transaction_type') == 'consommation_station' and not vals.get('regularization_state'):
                vals['regularization_state'] = 'pending'
        return super().create(vals_list)

    @api.depends('line_ids.amount', 'line_ids.qty')
    def _compute_totals(self):
        for rec in self:
            rec.amount_total = sum(rec.line_ids.mapped('amount'))
            rec.qty_total = sum(rec.line_ids.mapped('qty'))

    @api.model
    def log(self, transaction_type, company, wallet=False, purchase=False, qr=False, parent_qr=False, station=False, transfer=False, ticket_transfer=False, lines=False, note=False, idempotency_key=False, request_hash=False):
        vals = {
            'transaction_type': transaction_type,
            'company_id': company.id,
            'wallet_id': wallet.id if wallet else False,
            'purchase_id': purchase.id if purchase else False,
            'qr_id': qr.id if qr else False,
            'parent_qr_id': parent_qr.id if parent_qr else False,
            'station_id': station.id if station else False,
            'transfer_id': transfer.id if transfer else False,
            'ticket_transfer_id': ticket_transfer.id if ticket_transfer else False,
            'note': note or False,
            'idempotency_key': idempotency_key or False,
            'request_hash': request_hash or False,
        }
        if transaction_type == 'consommation_station':
            vals['regularization_state'] = 'pending'
        tx = self.sudo().create(vals)
        for line in lines or []:
            self.env['acpec.fuel.transaction.line'].sudo().create(dict(line, transaction_id=tx.id))
        return tx

    @api.constrains(
        'transaction_type',
        'regularization_state',
        'regularization_reference',
        'regularization_date',
        'regularized_by_id',
    )
    def _check_station_regularization_consistency(self):
        for rec in self:
            has_regularization_data = bool(
                rec.regularization_state
                or rec.regularization_reference
                or rec.regularization_date
                or rec.regularized_by_id
            )
            if rec.transaction_type != 'consommation_station':
                if has_regularization_data:
                    raise ValidationError(_('La régularisation station est réservée aux consommations station.'))
                continue

            if rec.regularization_state not in ('pending', 'regularized'):
                raise ValidationError(_('Une consommation station doit avoir un état de régularisation.'))

            if rec.regularization_state == 'pending':
                if rec.regularization_reference or rec.regularization_date or rec.regularized_by_id:
                    raise ValidationError(_('Une consommation station en attente ne doit pas porter de référence de régularisation.'))
                continue

            if not rec.regularization_reference:
                raise ValidationError(_('La référence de régularisation est obligatoire.'))
            if not rec.regularization_date:
                raise ValidationError(_('La date de régularisation est obligatoire.'))
            if not rec.regularized_by_id:
                raise ValidationError(_('L’utilisateur de régularisation est obligatoire.'))

    def _check_station_regularization_allowed(self):
        user = self.env.user
        if getattr(user, 'mobile_only', False):
            raise AccessError(_('La régularisation station est réservée au back-office.'))
        if not (
            user.has_group('acpec_fueltoken_base.group_fuel_admin')
            or user.has_group('acpec_fueltoken_base.group_fuel_manager')
        ):
            raise AccessError(_('Droits insuffisants pour régulariser une consommation station.'))
        return True

    def action_mark_station_regularized(self, reference):
        reference = str(reference or '').strip()
        if not reference:
            raise ValidationError(_('La référence de régularisation est obligatoire.'))
        self._check_station_regularization_allowed()

        records = self.sudo()
        non_station = records.filtered(lambda tx: tx.transaction_type != 'consommation_station')
        if non_station:
            raise ValidationError(_('Seules les consommations station peuvent être régularisées.'))

        different_reference = records.filtered(
            lambda tx: tx.regularization_state == 'regularized'
            and tx.regularization_reference
            and tx.regularization_reference != reference
        )
        if different_reference:
            raise UserError(_('Une ou plusieurs consommations sont déjà régularisées avec une autre référence.'))

        to_regularize = records.filtered(lambda tx: tx.regularization_state != 'regularized')
        if to_regularize:
            to_regularize.with_context(allow_fuel_transaction_regularization_update=True).write({
                'regularization_state': 'regularized',
                'regularization_reference': reference,
                'regularization_date': fields.Datetime.now(),
                'regularized_by_id': self.env.user.id,
            })
        return True

    def write(self, vals):
        regularization_fields = {
            'regularization_state',
            'regularization_reference',
            'regularization_date',
            'regularized_by_id',
        }
        vals_keys = set(vals)
        if vals_keys & regularization_fields and not self.env.context.get('allow_fuel_transaction_regularization_update'):
            raise UserError(_('La régularisation station doit passer par l’action dédiée.'))
        protected_keys = vals_keys - regularization_fields - {'note'}
        if protected_keys and not self.env.context.get('allow_fuel_transaction_update'):
            raise UserError(_('Les transactions Tickets Carburant ne doivent pas être modifiées directement.'))
        return super().write(vals)

    def init(self):
        # Backfill existing station consumption transactions created before Patch43H3B.
        self.env.cr.execute(
            """
            UPDATE acpec_fuel_transaction
               SET regularization_state = 'pending'
             WHERE transaction_type = 'consommation_station'
               AND regularization_state IS NULL
            """
        )

    def unlink(self):
        if not self.env.context.get('allow_fuel_transaction_unlink'):
            raise UserError(_('Les transactions Tickets Carburant sont append-only et ne doivent pas être supprimées.'))
        return super().unlink()


class AcpecFuelTransactionLine(models.Model):
    _name = 'acpec.fuel.transaction.line'
    _description = 'Ligne transaction Tickets Carburant'
    _order = 'transaction_id, id'

    transaction_id = fields.Many2one('acpec.fuel.transaction', string='Transaction', required=True, ondelete='cascade')
    company_id = fields.Many2one('res.company', related='transaction_id.company_id', store=True, readonly=True)
    currency_id = fields.Many2one('res.currency', related='transaction_id.currency_id', store=True, readonly=True)
    purchase_id = fields.Many2one('acpec.fuel.purchase', string='Lot d’achat', index=True)
    purchase_line_id = fields.Many2one('acpec.fuel.purchase.line', string='Ligne d’achat', index=True)
    face_line_id = fields.Many2one('acpec.fuel.face.line', string='Carnet', index=True)
    qr_id = fields.Many2one('acpec.fuel.qr', string='QR', index=True)
    qr_line_id = fields.Many2one('acpec.fuel.qr.line', string='Ligne QR', index=True)
    transfer_id = fields.Many2one('acpec.fuel.carnet.transfer', string='Transfert carnet', index=True)
    ticket_transfer_id = fields.Many2one('acpec.fuel.ticket.transfer', string='Transfert ticket', index=True)
    face_value = fields.Monetary(string='Valeur de face', required=True)
    qty = fields.Integer(string='Quantité', required=True)
    amount = fields.Monetary(string='Montant', compute='_compute_amount', store=True)

    @api.depends('face_value', 'qty')
    def _compute_amount(self):
        for rec in self:
            rec.amount = rec.face_value * rec.qty

    def write(self, vals):
        if vals and not self.env.context.get('allow_fuel_transaction_update'):
            raise UserError(_('Les lignes de transaction Tickets Carburant ne doivent pas être modifiées directement.'))
        return super().write(vals)

    def init(self):
        # Backfill existing station consumption transactions created before Patch43H3B.
        self.env.cr.execute(
            """
            UPDATE acpec_fuel_transaction
               SET regularization_state = 'pending'
             WHERE transaction_type = 'consommation_station'
               AND regularization_state IS NULL
            """
        )

    def unlink(self):
        if not self.env.context.get('allow_fuel_transaction_unlink'):
            raise UserError(_('Les lignes de transaction Tickets Carburant sont append-only et ne doivent pas être supprimées.'))
        return super().unlink()
