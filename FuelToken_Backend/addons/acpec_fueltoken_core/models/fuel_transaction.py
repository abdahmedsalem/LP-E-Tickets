import secrets

from odoo import api, fields, models, _
from odoo.exceptions import AccessError, ValidationError, UserError


class AcpecFuelTransaction(models.Model):
    _name = 'acpec.fuel.transaction'
    _description = 'Transaction Tickets Carburant'
    _order = 'id desc'

    TX_REFERENCE_PREFIX = 'TX'
    TX_REFERENCE_RANDOM_DIGITS = 12
    TX_REFERENCE_MAX_RETRIES = 20

    _sql_constraints = [
        ('name_uniq', 'unique(name)', 'La référence de transaction doit être unique.'),
    ]

    name = fields.Char(
        string='Référence',
        default='New',
        readonly=True,
        copy=False,
        index=True,
        help="Référence publique non énumérable au format TX-YYYYMMDD-HHMMSS-NNNNNNNNNNNN. L'id base de données reste interne.",
    )
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
    partner_id = fields.Many2one(
        'res.partner',
        string='Partenaire wallet',
        related='wallet_id.partner_id',
        store=True,
        readonly=True,
        index=True,
        help="Partenaire du wallet de cette ligne transactionnelle. Ce champ porte la perspective/propriété du portefeuille et ne doit pas être confondu avec l'acteur global de l'opération.",
    )
    actor_partner_id = fields.Many2one(
        'res.partner',
        string='Partenaire acteur',
        readonly=True,
        copy=False,
        index=True,
        help="Snapshot audit du partenaire de celui qui exécute/initie l'opération. Ce champ ne remplace pas partner_id, qui reste le partenaire du wallet de la ligne transactionnelle.",
    )
    counterparty_partner_id = fields.Many2one(
        'res.partner',
        string='Partenaire contrepartie',
        readonly=True,
        copy=False,
        index=True,
        help="Snapshot audit de l'autre partie métier de l'opération : destinataire pour un transfert, propriétaire du QR/ticket pour une consommation station.",
    )
    counterparty_user_id = fields.Many2one(
        'res.users',
        string='Utilisateur contrepartie',
        readonly=True,
        copy=False,
        index=True,
        help="Utilisateur technique de la contrepartie lorsque la résolution depuis le partenaire est unique. Le partenaire reste l'identité métier canonique.",
    )
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


    @api.model
    def _generate_transaction_reference_candidate(self):
        now = fields.Datetime.now()
        if not hasattr(now, 'strftime'):
            now = fields.Datetime.to_datetime(now)
        suffix = str(secrets.randbelow(10 ** self.TX_REFERENCE_RANDOM_DIGITS)).zfill(self.TX_REFERENCE_RANDOM_DIGITS)
        return '%s-%s-%s' % (
            self.TX_REFERENCE_PREFIX,
            now.strftime('%Y%m%d-%H%M%S'),
            suffix,
        )

    @api.model
    def _generate_unique_transaction_reference(self, reserved_names=False):
        reserved_names = reserved_names or set()
        for _attempt in range(self.TX_REFERENCE_MAX_RETRIES):
            name = self._generate_transaction_reference_candidate()
            if name in reserved_names:
                continue
            if not self.sudo().search_count([('name', '=', name)]):
                return name
        raise UserError('Impossible de générer une référence transaction unique.')

    @api.model_create_multi
    def create(self, vals_list):
        reserved_names = set()
        for vals in vals_list:
            # Transaction references are public wallet identifiers. Do not expose
            # Odoo sequences or database ids. Also ignore manually supplied names
            # unless an explicit internal rescue context is used.
            if (
                vals.get('name') in (False, None, '', 'New')
                or not self.env.context.get('allow_fuel_transaction_name_override')
            ):
                vals['name'] = self._generate_unique_transaction_reference(reserved_names)
            reserved_names.add(vals.get('name'))
            if vals.get('transaction_type') == 'consommation_station' and not vals.get('regularization_state'):
                vals['regularization_state'] = 'pending'
        return super().create(vals_list)

    @api.depends('line_ids.amount', 'line_ids.qty')
    def _compute_totals(self):
        for rec in self:
            rec.amount_total = sum(rec.line_ids.mapped('amount'))
            rec.qty_total = sum(rec.line_ids.mapped('qty'))

    @api.model
    def _single_user_for_partner(self, partner):
        """Return a unique user for a partner when resolution is unambiguous."""
        if not partner:
            return self.env['res.users']
        partner = partner.sudo().exists()
        if not partner:
            return self.env['res.users']
        users = self.env['res.users'].sudo().with_context(active_test=False).search([
            ('partner_id', '=', partner.id),
        ], limit=2)
        return users if len(users) == 1 else self.env['res.users']

    @api.model
    def log(
        self,
        transaction_type,
        company,
        wallet=False,
        purchase=False,
        qr=False,
        parent_qr=False,
        station=False,
        transfer=False,
        ticket_transfer=False,
        lines=False,
        note=False,
        idempotency_key=False,
        request_hash=False,
        actor_partner=False,
        counterparty_partner=False,
        counterparty_user=False,
    ):
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
            'actor_partner_id': actor_partner.id if actor_partner else False,
            'counterparty_partner_id': counterparty_partner.id if counterparty_partner else False,
            'counterparty_user_id': counterparty_user.id if counterparty_user else False,
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

        # Backfill actor/counterparty snapshots introduced by Patch43M5.
        # Kept additive: old partner_id, source/dest transfer rules and reports remain unchanged.
        self.env.cr.execute(
            """
            UPDATE acpec_fuel_qr q
               SET consumed_partner_id = u.partner_id
              FROM res_users u
             WHERE q.consumed_partner_id IS NULL
               AND q.consumed_user_id = u.id
               AND u.partner_id IS NOT NULL
            """
        )
        self.env.cr.execute(
            """
            UPDATE acpec_fuel_transaction t
               SET actor_partner_id = COALESCE(t.actor_partner_id, q.consumed_partner_id, u.partner_id),
                   counterparty_partner_id = COALESCE(t.counterparty_partner_id, w.partner_id)
              FROM acpec_fuel_qr q
              LEFT JOIN res_users u ON u.id = q.consumed_user_id
              LEFT JOIN acpec_fuel_wallet w ON w.id = q.wallet_id
             WHERE t.transaction_type = 'consommation_station'
               AND t.qr_id = q.id
               AND (t.actor_partner_id IS NULL OR t.counterparty_partner_id IS NULL)
            """
        )
        self.env.cr.execute(
            """
            UPDATE acpec_fuel_transaction t
               SET actor_partner_id = COALESCE(t.actor_partner_id, sw.partner_id),
                   counterparty_partner_id = COALESCE(t.counterparty_partner_id, dw.partner_id)
              FROM acpec_fuel_carnet_transfer tr
              LEFT JOIN acpec_fuel_wallet sw ON sw.id = tr.source_wallet_id
              LEFT JOIN acpec_fuel_wallet dw ON dw.id = tr.dest_wallet_id
             WHERE t.transfer_id = tr.id
               AND (t.actor_partner_id IS NULL OR t.counterparty_partner_id IS NULL)
            """
        )
        self.env.cr.execute(
            """
            UPDATE acpec_fuel_transaction t
               SET actor_partner_id = COALESCE(t.actor_partner_id, sw.partner_id),
                   counterparty_partner_id = COALESCE(t.counterparty_partner_id, dw.partner_id)
              FROM acpec_fuel_ticket_transfer tr
              LEFT JOIN acpec_fuel_wallet sw ON sw.id = tr.source_wallet_id
              LEFT JOIN acpec_fuel_wallet dw ON dw.id = tr.dest_wallet_id
             WHERE t.ticket_transfer_id = tr.id
               AND (t.actor_partner_id IS NULL OR t.counterparty_partner_id IS NULL)
            """
        )
        self.env.cr.execute(
            """
            WITH partner_users AS (
                SELECT partner_id, MIN(id) AS user_id
                  FROM res_users
                 WHERE partner_id IS NOT NULL
                 GROUP BY partner_id
                HAVING COUNT(*) = 1
            )
            UPDATE acpec_fuel_transaction t
               SET counterparty_user_id = pu.user_id
              FROM partner_users pu
             WHERE t.counterparty_partner_id = pu.partner_id
               AND t.counterparty_user_id IS NULL
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
