from odoo import api, fields, models, _
from odoo.exceptions import AccessError, UserError, ValidationError


class AcpecFuelTicketTransfer(models.Model):
    _name = 'acpec.fuel.ticket.transfer'
    _description = 'Transfert de tickets'
    _inherit = ['mail.thread', 'mail.activity.mixin', 'acpec.fuel.public.code.mixin']
    _order = 'id desc'

    name = fields.Char(string='Référence interne', default='New', readonly=True, copy=False)
    source_wallet_id = fields.Many2one(
        'acpec.fuel.wallet', string='Compte source',
        required=True, index=True, ondelete='restrict', tracking=True,
    )
    source_partner_id = fields.Many2one(
        'res.partner', string='Partenaire source', related='source_wallet_id.partner_id',
        store=True, readonly=True, index=True,
    )
    dest_wallet_id = fields.Many2one(
        'acpec.fuel.wallet', string='Compte destinataire',
        required=True, index=True, ondelete='restrict', tracking=True,
    )
    dest_partner_id = fields.Many2one(
        'res.partner', string='Partenaire destinataire', related='dest_wallet_id.partner_id',
        store=True, readonly=True, index=True,
    )
    company_id = fields.Many2one(
        'res.company', string='Société',
        required=True, default=lambda self: self.env.company, index=True,
    )
    currency_id = fields.Many2one(
        'res.currency', related='company_id.currency_id',
        store=True, readonly=True,
    )
    state = fields.Selection([
        ('draft', 'Brouillon'),
        ('confirmed', 'Confirmé'),
        ('cancelled', 'Annulé'),
    ], string='État', default='draft', required=True, index=True, tracking=True)
    line_ids = fields.One2many(
        'acpec.fuel.ticket.transfer.line', 'transfer_id', string='Lignes',
    )
    note = fields.Text(string='Motif / note')
    idempotency_key = fields.Char(string='Clé idempotence', index=True, copy=False)
    request_hash = fields.Char(string='Hash requête idempotence', index=True, copy=False)
    confirmed_at = fields.Datetime(string='Confirmé le', readonly=True, copy=False)
    confirmed_by = fields.Many2one(
        'res.users', string='Confirmé par', readonly=True, copy=False,
    )
    amount_total = fields.Monetary(
        string='Montant total', compute='_compute_totals', store=True,
    )
    face_qty_total = fields.Integer(
        string='Nombre total de tickets', compute='_compute_totals', store=True,
    )

    _idempotency_source_wallet_unique = models.Constraint(
        'UNIQUE(source_wallet_id, idempotency_key)',
        "Cette operation de transfert ticket a deja ete enregistree pour ce compte source.",
    )

    _internal_operation_context = (
        'acpec_fueltoken_ticket_transfer_internal_operation'
    )
    _internal_actor_context = (
        'acpec_fueltoken_ticket_transfer_internal_actor_user_id'
    )
    _internal_write_fields = {
        'confirmation_write': frozenset((
            'state',
            'confirmed_at',
            'confirmed_by',
        )),
        'cancellation_write': frozenset((
            'state',
        )),
        'mobile_audit_write': frozenset((
            'mobile_session_id',
            'device_uid',
        )),
    }

    @api.model
    def _ticket_transfer_internal_context_is_valid(self, operation):
        return (
            self.env.su
            and self.env.context.get(self._internal_operation_context) == operation
        )

    @api.model
    def _create_internal(self, vals_list):
        transfers = self.sudo().with_context(
            acpec_fueltoken_ticket_transfer_internal_operation='create',
            acpec_fueltoken_ticket_transfer_line_internal_operation='create',
        ).create(vals_list)
        return self.sudo().with_context(
            acpec_fueltoken_ticket_transfer_internal_operation=False,
            acpec_fueltoken_ticket_transfer_internal_actor_user_id=False,
            acpec_fueltoken_ticket_transfer_line_internal_operation=False,
        ).browse(transfers.ids)

    def _write_confirmation_internal(self, vals):
        return self.sudo().with_context(
            acpec_fueltoken_ticket_transfer_internal_operation='confirmation_write',
        ).write(vals)

    def _write_cancellation_internal(self, vals):
        return self.sudo().with_context(
            acpec_fueltoken_ticket_transfer_internal_operation='cancellation_write',
        ).write(vals)

    def _write_mobile_audit_internal(self, vals):
        return self.sudo().with_context(
            acpec_fueltoken_ticket_transfer_internal_operation='mobile_audit_write',
        ).write(vals)

    def _confirm_internal(self, actor_user):
        actor_id = (
            actor_user.id
            if hasattr(actor_user, 'id')
            else int(actor_user or 0)
        )
        actor = self.env['res.users'].sudo().browse(actor_id).exists()
        if not actor:
            raise AccessError(_('Acteur interne de confirmation introuvable.'))
        return self.sudo().with_context(
            acpec_fueltoken_ticket_transfer_internal_operation='confirm',
            acpec_fueltoken_ticket_transfer_internal_actor_user_id=actor.id,
        ).action_confirm(actor_user=actor)

    def _cancel_internal(self, actor_user):
        actor_id = (
            actor_user.id
            if hasattr(actor_user, 'id')
            else int(actor_user or 0)
        )
        actor = self.env['res.users'].sudo().browse(actor_id).exists()
        if not actor:
            raise AccessError(_('Acteur interne d’annulation introuvable.'))
        return self.sudo().with_context(
            acpec_fueltoken_ticket_transfer_internal_operation='cancel',
            acpec_fueltoken_ticket_transfer_internal_actor_user_id=actor.id,
        ).action_cancel(actor_user=actor)

    def _ticket_transfer_action_actor(self, operation, actor_user):
        if not self._ticket_transfer_internal_context_is_valid(operation):
            raise AccessError(_(
                "L’action sur le transfert de tickets est réservée "
                "aux flux internes contrôlés."
            ))

        explicit_actor_id = (
            actor_user.id
            if hasattr(actor_user, 'id')
            else int(actor_user or 0)
        )
        context_actor_id = int(
            self.env.context.get(self._internal_actor_context) or 0
        )
        if not explicit_actor_id or explicit_actor_id != context_actor_id:
            raise AccessError(_(
                "L’acteur du transfert de tickets ne correspond pas "
                "au contexte interne."
            ))

        actor = self.env['res.users'].sudo().browse(context_actor_id).exists()
        if not actor:
            raise AccessError(_('Acteur du transfert de tickets introuvable.'))
        return actor

    @api.model_create_multi
    def create(self, vals_list):
        if not self._ticket_transfer_internal_context_is_valid('create'):
            raise AccessError(_(
                "La création d’un transfert de tickets est réservée "
                "aux flux internes contrôlés."
            ))
        for vals in vals_list:
            if (
                vals.get('state', 'draft') != 'draft'
                or vals.get('confirmed_at')
                or vals.get('confirmed_by')
                or vals.get('mobile_session_id')
                or vals.get('device_uid')
            ):
                raise AccessError(_(
                    "Un transfert de tickets doit être créé en brouillon "
                    "sans audit de confirmation prérempli."
                ))
            if vals.get('name', 'New') == 'New':
                vals['name'] = (
                    self.env['ir.sequence'].next_by_code('acpec.fuel.ticket.transfer') or 'New'
                )
            if not vals.get('public_code'):
                vals['public_code'] = self._create_unique_public_code(prefix='TTF', size=18)
        return super().create(vals_list)

    @api.depends('line_ids.qty_faces', 'line_ids.amount_total')
    def _compute_totals(self):
        for rec in self:
            rec.face_qty_total = sum(rec.line_ids.mapped('qty_faces'))
            rec.amount_total = sum(rec.line_ids.mapped('amount_total'))

    @api.constrains('source_wallet_id', 'dest_wallet_id', 'company_id')
    def _check_wallets(self):
        for rec in self:
            if rec.source_wallet_id == rec.dest_wallet_id:
                raise ValidationError(_('Le compte source et le compte destinataire doivent être différents.'))
            if rec.source_wallet_id.company_id != rec.company_id:
                raise ValidationError(_('Le compte source doit appartenir à la même société que le transfert.'))
            if rec.dest_wallet_id.company_id != rec.company_id:
                raise ValidationError(_('Le compte destinataire doit appartenir à la même société que le transfert.'))

    def write(self, vals):
        if not vals:
            return True

        operation = self.env.context.get(self._internal_operation_context)
        expected_fields = self._internal_write_fields.get(operation)
        if (
            not expected_fields
            or not self._ticket_transfer_internal_context_is_valid(operation)
            or set(vals) != expected_fields
        ):
            raise AccessError(_(
                "La modification d’un transfert de tickets est réservée "
                "à une opération interne précise."
            ))

        if operation == 'confirmation_write':
            if (
                vals.get('state') != 'confirmed'
                or not vals.get('confirmed_at')
                or not vals.get('confirmed_by')
            ):
                raise AccessError(_('Audit de confirmation incomplet.'))
            if any(record.state != 'draft' for record in self):
                raise AccessError(_(
                    "Seul un transfert de tickets en brouillon peut être confirmé."
                ))

        elif operation == 'cancellation_write':
            if vals.get('state') != 'cancelled':
                raise AccessError(_('État d’annulation invalide.'))
            if any(record.state != 'draft' for record in self):
                raise AccessError(_(
                    "Seul un transfert de tickets en brouillon peut être annulé."
                ))

        elif operation == 'mobile_audit_write':
            if not vals.get('mobile_session_id') or not vals.get('device_uid'):
                raise AccessError(_('Audit mobile incomplet.'))
            for record in self:
                if record.state != 'confirmed':
                    raise AccessError(_(
                        "L’audit mobile exige un transfert de tickets confirmé."
                    ))
                if record.mobile_session_id or record.device_uid:
                    raise AccessError(_(
                        "L’audit mobile du transfert de tickets est initialisé une seule fois."
                    ))

        return super().write(vals)

    def unlink(self):
        raise UserError(_(
            'Les transferts de tickets ne peuvent jamais être supprimés.'
        ))

    def _prepare_fragment_identity_vals(self, source_face_line, transfer_line):
        self.ensure_one()
        FaceLine = self.env['acpec.fuel.face.line'].sudo()
        transfer_ref = (self.name or ('TTR-%s' % self.id)).replace('/', '-')
        carnet_no = '%s-F%03d' % (transfer_ref, transfer_line.id)
        return {
            'carnet_no': carnet_no,
            'lot_short_code': source_face_line.lot_short_code or FaceLine._generate_lot_short_code(self.company_id),
            'carnet_short_code': FaceLine._generate_carnet_short_code(self.company_id),
            'carnet_sequence': transfer_line.id,
        }

    def action_confirm(self, actor_user=None):
        """Confirme un transfert de tickets disponibles."""
        self.ensure_one()
        actor_user = self._ticket_transfer_action_actor(
            'confirm',
            actor_user,
        )
        if self.state == 'confirmed':
            return True

        if self.state != 'draft':
            raise UserError(_('Seul un transfert ticket en brouillon peut être confirmé.'))
        if self.source_wallet_id == self.dest_wallet_id:
            raise ValidationError(_('Le compte source et le compte destinataire doivent être différents.'))
        if not self.line_ids:
            raise UserError(_('Le transfert ticket doit contenir au moins une ligne.'))

        FaceLine = self.env['acpec.fuel.face.line'].sudo()
        Tx = self.env['acpec.fuel.transaction'].sudo()
        now = fields.Datetime.now()

        with self.env.cr.savepoint():
            self.env.cr.execute(
                'SELECT id FROM acpec_fuel_wallet WHERE id IN %s FOR UPDATE',
                [tuple((self.source_wallet_id | self.dest_wallet_id).ids)],
            )
            src_face_line_ids = tuple(self.line_ids.mapped('source_face_line_id').ids)
            if not src_face_line_ids:
                raise ValidationError(_('Aucune ligne source valide dans le transfert ticket.'))
            self.env.cr.execute(
                'SELECT id FROM acpec_fuel_face_line WHERE id IN %s FOR UPDATE',
                [src_face_line_ids],
            )
            self.line_ids.mapped('source_face_line_id').invalidate_recordset()

            src_tx_lines = []
            dst_tx_lines = []

            for trf_line in self.line_ids:
                src_face_line = trf_line.source_face_line_id
                qty_to_transfer = int(trf_line.qty_faces or 0)

                if trf_line.dest_face_line_id:
                    continue
                if qty_to_transfer <= 0:
                    raise ValidationError(_('La quantité de tickets à transférer doit être strictement positive.'))
                if src_face_line.wallet_id != self.source_wallet_id:
                    raise ValidationError(_(
                        "La ligne '%s' n'appartient pas au compte source."
                    ) % (src_face_line.carnet_short_code or src_face_line.carnet_no or src_face_line.id))
                if src_face_line.company_id != self.company_id:
                    raise ValidationError(_('La ligne source doit appartenir à la même société que le transfert.'))
                if src_face_line.expires_at and src_face_line.expires_at <= now:
                    raise ValidationError(_(
                        "La ligne '%s' est expirée et ne peut pas être transférée."
                    ) % (src_face_line.carnet_short_code or src_face_line.carnet_no or src_face_line.id))
                if src_face_line.qty_available < qty_to_transfer:
                    raise ValidationError(_(
                        "Tickets disponibles insuffisants pour '%s' : %d disponibles, %d demandés."
                    ) % (
                        src_face_line.carnet_short_code or src_face_line.carnet_no or src_face_line.id,
                        src_face_line.qty_available,
                        qty_to_transfer,
                    ))

                identity_vals = self._prepare_fragment_identity_vals(src_face_line, trf_line)
                dest_face_line = FaceLine._create_internal(dict(identity_vals, **{
                    'wallet_id': self.dest_wallet_id.id,
                    'purchase_id': src_face_line.purchase_id.id,
                    'purchase_line_id': src_face_line.purchase_line_id.id,
                    'carnet_type_id': src_face_line.carnet_type_id.id,
                    'face_value': src_face_line.face_value,
                    'qty_initial': qty_to_transfer,
                    'qty_available': qty_to_transfer,
                    'expires_at': src_face_line.expires_at,
                    'origin_face_line_id': src_face_line.id,
                    'origin_ticket_transfer_line_id': trf_line.id,
                    'is_transfer_fragment': True,
                }))

                src_face_line._write_state_internal({
                    'qty_available': src_face_line.qty_available - qty_to_transfer,
                    'qty_transferred_out': src_face_line.qty_transferred_out + qty_to_transfer,
                })
                trf_line._write_destination_internal({
                    'dest_face_line_id': dest_face_line.id,
                })

                src_tx_lines.append({
                    'face_line_id': src_face_line.id,
                    'purchase_id': src_face_line.purchase_id.id,
                    'purchase_line_id': src_face_line.purchase_line_id.id,
                    'ticket_transfer_id': self.id,
                    'face_value': src_face_line.face_value,
                    'qty': qty_to_transfer,
                })
                dst_tx_lines.append({
                    'face_line_id': dest_face_line.id,
                    'purchase_id': src_face_line.purchase_id.id,
                    'purchase_line_id': src_face_line.purchase_line_id.id,
                    'ticket_transfer_id': self.id,
                    'face_value': src_face_line.face_value,
                    'qty': qty_to_transfer,
                })

            counterparty_user = Tx._single_user_for_partner(self.dest_partner_id)
            note_text = (self.note or '').strip()
            outgoing_note = _('Transfert ticket sortant vers %s') % (self.dest_partner_id.display_name)
            incoming_note = _('Transfert ticket entrant de %s') % (self.source_partner_id.display_name)
            if note_text:
                outgoing_note = '%s. %s' % (outgoing_note, _('Motif : %s') % note_text)
                incoming_note = '%s. %s' % (incoming_note, _('Motif : %s') % note_text)

            if src_tx_lines:
                Tx.log(
                    'transfert_ticket', self.company_id,
                    wallet=self.source_wallet_id,
                    ticket_transfer=self,
                    lines=src_tx_lines,
                    note=outgoing_note,
                    transaction_effect='outgoing',
                    idempotency_key='SRC-TKT-%s' % (self.idempotency_key or str(self.id)),
                    request_hash=self.request_hash,
                    actor_partner=self.source_partner_id,
                    counterparty_partner=self.dest_partner_id,
                    counterparty_user=counterparty_user,
                )
                Tx.log(
                    'transfert_ticket', self.company_id,
                    wallet=self.dest_wallet_id,
                    ticket_transfer=self,
                    lines=dst_tx_lines,
                    note=incoming_note,
                    transaction_effect='incoming',
                    idempotency_key='DST-TKT-%s' % (self.idempotency_key or str(self.id)),
                    request_hash=self.request_hash,
                    actor_partner=self.source_partner_id,
                    counterparty_partner=self.dest_partner_id,
                    counterparty_user=counterparty_user,
                )

            self._write_confirmation_internal({
                'state': 'confirmed',
                'confirmed_at': now,
                'confirmed_by': actor_user.id,
            })
        return True

    def action_cancel(self, actor_user=None):
        self.ensure_one()
        actor_user = self._ticket_transfer_action_actor(
            'cancel',
            actor_user,
        )
        if self.state == 'confirmed':
            raise UserError(_(
                "Un transfert ticket déjà confirmé ne peut pas être annulé. "
                "Créez un transfert inverse si nécessaire."
            ))
        if self.state == 'cancelled':
            return True
        self._write_cancellation_internal({'state': 'cancelled'})
        return True


class AcpecFuelTicketTransferLine(models.Model):
    _name = 'acpec.fuel.ticket.transfer.line'
    _description = 'Ligne de transfert de tickets'
    _order = 'transfer_id, id'

    transfer_id = fields.Many2one(
        'acpec.fuel.ticket.transfer', string='Transfert ticket',
        required=True, ondelete='cascade', index=True,
    )
    company_id = fields.Many2one(
        'res.company', related='transfer_id.company_id', store=True, readonly=True,
    )
    currency_id = fields.Many2one(
        'res.currency', related='transfer_id.currency_id', store=True, readonly=True,
    )
    source_face_line_id = fields.Many2one(
        'acpec.fuel.face.line', string='Ligne source',
        required=True, index=True, ondelete='restrict',
    )
    dest_face_line_id = fields.Many2one(
        'acpec.fuel.face.line', string='Fragment destination',
        readonly=True, copy=False, index=True,
    )
    carnet_type_id = fields.Many2one(
        'acpec.fuel.carnet.type', related='source_face_line_id.carnet_type_id',
        store=True, readonly=True,
    )
    face_value = fields.Monetary(
        related='source_face_line_id.face_value', store=True, readonly=True,
    )
    qty_faces = fields.Integer(string='Tickets transférés', required=True)
    amount_total = fields.Monetary(
        string='Montant', compute='_compute_amount_total', store=True,
    )

    _internal_operation_context = (
        'acpec_fueltoken_ticket_transfer_line_internal_operation'
    )
    _destination_write_fields = frozenset((
        'dest_face_line_id',
    ))

    @api.model
    def _ticket_transfer_line_internal_context_is_valid(self, operation):
        return (
            self.env.su
            and self.env.context.get(self._internal_operation_context) == operation
        )

    @api.model
    def _create_internal(self, vals_list):
        lines = self.sudo().with_context(
            acpec_fueltoken_ticket_transfer_line_internal_operation='create',
        ).create(vals_list)
        return self.sudo().with_context(
            acpec_fueltoken_ticket_transfer_line_internal_operation=False,
        ).browse(lines.ids)

    def _write_destination_internal(self, vals):
        return self.sudo().with_context(
            acpec_fueltoken_ticket_transfer_line_internal_operation='destination_write',
        ).write(vals)

    @api.model_create_multi
    def create(self, vals_list):
        if not self._ticket_transfer_line_internal_context_is_valid('create'):
            raise AccessError(_(
                "La création d’une ligne de transfert de tickets est réservée "
                "aux flux internes contrôlés."
            ))
        if any(vals.get('dest_face_line_id') for vals in vals_list):
            raise AccessError(_(
                "Le fragment destination ne peut pas être prérempli."
            ))
        return super().create(vals_list)

    @api.depends('qty_faces', 'face_value')
    def _compute_amount_total(self):
        for rec in self:
            rec.amount_total = (rec.qty_faces or 0) * (rec.face_value or 0)

    @api.constrains('qty_faces')
    def _check_qty_faces(self):
        for rec in self:
            if rec.qty_faces <= 0:
                raise ValidationError(_('Le nombre de tickets à transférer doit être strictement positif.'))

    def write(self, vals):
        if not vals:
            return True
        if (
            not self._ticket_transfer_line_internal_context_is_valid(
                'destination_write'
            )
            or set(vals) != self._destination_write_fields
            or not vals.get('dest_face_line_id')
        ):
            raise AccessError(_(
                "La modification d’une ligne de transfert de tickets est "
                "réservée à l’affectation interne du fragment destination."
            ))

        for record in self:
            if record.transfer_id.state != 'draft':
                raise AccessError(_(
                    "Le fragment destination doit être affecté avant "
                    "la confirmation du transfert."
                ))
            if record.dest_face_line_id:
                raise AccessError(_(
                    "Le fragment destination est initialisé une seule fois."
                ))
        return super().write(vals)

    def unlink(self):
        raise UserError(_(
            'Les lignes de transfert de tickets ne peuvent jamais être supprimées.'
        ))
