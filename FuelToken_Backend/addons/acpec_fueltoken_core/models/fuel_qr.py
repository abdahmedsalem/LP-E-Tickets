import logging

from odoo import api, fields, models, _
from odoo.exceptions import ValidationError, UserError

_logger = logging.getLogger(__name__)


class AcpecFuelQr(models.Model):
    _name = 'acpec.fuel.qr'
    _description = 'Bon de retrait'
    _inherit = ['mail.thread', 'mail.activity.mixin', 'acpec.fuel.public.code.mixin']
    _order = 'id desc'

    name = fields.Char(string='Référence interne', default='New', readonly=True, copy=False)
    wallet_id = fields.Many2one('acpec.fuel.wallet', string='Compte Tickets Carburant', required=True, index=True)
    partner_id = fields.Many2one('res.partner', related='wallet_id.partner_id', store=True, readonly=True, index=True)
    company_id = fields.Many2one('res.company', related='wallet_id.company_id', store=True, readonly=True, index=True)
    currency_id = fields.Many2one('res.currency', related='wallet_id.currency_id', store=True, readonly=True)
    state = fields.Selection([
        ('active', 'Actif'),
        ('blocked', 'Bloqué'),
        ('split', 'Splitté'),
        ('consumed', 'Consommé'),
        ('expired', 'Expiré'),
    ], string='État', default='active', required=True, index=True, tracking=True)
    line_ids = fields.One2many('acpec.fuel.qr.line', 'qr_id', string='Lignes QR')
    parent_id = fields.Many2one('acpec.fuel.qr', string='QR parent', index=True, copy=False)
    child_ids = fields.One2many('acpec.fuel.qr', 'parent_id', string='QR enfants')
    consumed_station_id = fields.Many2one('acpec.fuel.station', string='Station de consommation', readonly=True)
    consumed_user_id = fields.Many2one('res.users', string='Utilisateur station', readonly=True)
    consumed_at = fields.Datetime(string='Date consommation', readonly=True)
    expires_at = fields.Datetime(string='Expiration', compute='_compute_totals', store=True)
    amount_total = fields.Monetary(string='Montant', compute='_compute_totals', store=True)
    face_qty_total = fields.Integer(string='Faces', compute='_compute_totals', store=True)
    idempotency_key = fields.Char(string='Clé idempotence', index=True, copy=False)
    request_hash = fields.Char(string='Hash requête idempotence', index=True, copy=False)

    _public_code_unique = models.Constraint(
        'UNIQUE(public_code)',
        'Le code public du QR doit etre unique.',
    )
    _idempotency_wallet_unique = models.Constraint(
        'UNIQUE(wallet_id, idempotency_key)',
        'Cette operation QR existe deja pour ce compte.',
    )
    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if vals.get('name', 'New') == 'New':
                vals['name'] = self.env['ir.sequence'].next_by_code('acpec.fuel.qr') or 'New'
            if not vals.get('public_code'):
                vals['public_code'] = self._create_unique_public_code(prefix='QR', size=24)
        return super().create(vals_list)

    @api.depends('line_ids.qty', 'line_ids.face_value', 'line_ids.expires_at')
    def _compute_totals(self):
        for rec in self:
            rec.amount_total = sum(rec.line_ids.mapped('amount'))
            rec.face_qty_total = sum(rec.line_ids.mapped('qty'))
            dates = [dt for dt in rec.line_ids.mapped('expires_at') if dt]
            rec.expires_at = min(dates) if dates else False

    def _lock_records(self):
        if self.ids:
            self.env.cr.execute('SELECT id FROM acpec_fuel_qr WHERE id IN %s FOR UPDATE', [tuple(self.ids)])

    @api.model
    def issue_from_available(self, wallet, requests, idempotency_key=False, request_hash=False):
        if idempotency_key:
            existing = self.sudo().search([('wallet_id', '=', wallet.id), ('idempotency_key', '=', idempotency_key)], limit=1)
            if existing:
                if existing.request_hash and request_hash and existing.request_hash != request_hash:
                    raise ValidationError(_('idempotency_conflict: même idempotency_key avec payload différent.'))
                return existing
        with self.env.cr.savepoint():
            # Verrou pessimiste sur le wallet pour éviter la double émission
            self.env.cr.execute(
                "SELECT id FROM acpec_fuel_wallet WHERE id = %s FOR UPDATE",
                (wallet.id,),
            )
            wallet.invalidate_recordset()
            qr = self.sudo().create({'wallet_id': wallet.id, 'idempotency_key': idempotency_key or False, 'request_hash': request_hash or False})
            allocations = self.env['acpec.fuel.face.line'].sudo().reserve_available(wallet, requests)
            tx_lines = []
            for allocation in allocations:
                face_line = allocation['face_line']
                qty = allocation['qty']
                qr_line = self.env['acpec.fuel.qr.line'].sudo().create({
                    'qr_id': qr.id,
                    'face_line_id': face_line.id,
                    'purchase_id': face_line.purchase_id.id,
                    'purchase_line_id': face_line.purchase_line_id.id,
                    'face_value': face_line.face_value,
                    'qty': qty,
                    'state': 'active',
                    'expires_at': face_line.expires_at,
                })
                tx_lines.append({
                    'purchase_id': face_line.purchase_id.id,
                    'purchase_line_id': face_line.purchase_line_id.id,
                    'face_line_id': face_line.id,
                    'qr_id': qr.id,
                    'qr_line_id': qr_line.id,
                    'face_value': face_line.face_value,
                    'qty': qty,
                })
            if not qr.line_ids:
                raise ValidationError(_('Un QR doit contenir au moins une ligne.'))
            self.env['acpec.fuel.transaction'].log('emission_qr', qr.company_id, wallet=wallet, qr=qr, lines=tx_lines, idempotency_key=idempotency_key)
            return qr

    def _has_expired_lines(self):
        now = fields.Datetime.now()
        return any(line.expires_at and line.expires_at <= now for line in self.line_ids if line.state in ('active', 'blocked'))

    def action_refresh_expiration_state(self):
        now = fields.Datetime.now()
        for qr in self:
            if qr.state not in ('active', 'blocked'):
                continue
            candidate_lines = qr.line_ids.filtered(lambda l: l.state in ('active', 'blocked'))
            if not candidate_lines:
                continue
            expired = candidate_lines.filtered(lambda l: l.expires_at and l.expires_at <= now)
            valid = candidate_lines - expired
            if not expired:
                continue
            if valid:
                qr._block_with_expired_lines(expired, valid)
            else:
                qr._expire_all_lines(expired)

    def _block_with_expired_lines(self, expired_lines, valid_lines):
        tx_lines = []
        for line in expired_lines:
            if line.state == 'active':
                line.face_line_id.write({
                    'qty_qr_active': line.face_line_id.qty_qr_active - line.qty,
                    'qty_expired': line.face_line_id.qty_expired + line.qty,
                })
            elif line.state == 'blocked':
                line.face_line_id.write({
                    'qty_qr_blocked': line.face_line_id.qty_qr_blocked - line.qty,
                    'qty_expired': line.face_line_id.qty_expired + line.qty,
                })
            line.write({'state': 'expired'})
            tx_lines.append(line._transaction_line_vals())
        for line in valid_lines.filtered(lambda l: l.state == 'active'):
            line.face_line_id.write({
                'qty_qr_active': line.face_line_id.qty_qr_active - line.qty,
                'qty_qr_blocked': line.face_line_id.qty_qr_blocked + line.qty,
            })
            line.write({'state': 'blocked'})
        self.write({'state': 'blocked'})
        self.env['acpec.fuel.transaction'].log('blocage_qr', self.company_id, wallet=self.wallet_id, qr=self, lines=tx_lines, note=_('QR bloqué par expiration partielle.'))

    def _expire_all_lines(self, expired_lines):
        tx_lines = []
        for line in expired_lines:
            if line.state == 'active':
                line.face_line_id.write({
                    'qty_qr_active': line.face_line_id.qty_qr_active - line.qty,
                    'qty_expired': line.face_line_id.qty_expired + line.qty,
                })
            elif line.state == 'blocked':
                line.face_line_id.write({
                    'qty_qr_blocked': line.face_line_id.qty_qr_blocked - line.qty,
                    'qty_expired': line.face_line_id.qty_expired + line.qty,
                })
            line.write({'state': 'expired'})
            tx_lines.append(line._transaction_line_vals())
        self.write({'state': 'expired'})
        self.env['acpec.fuel.transaction'].log('expiration_qr', self.company_id, wallet=self.wallet_id, qr=self, lines=tx_lines, note=_('QR entièrement expiré.'))

    def action_consume_by_station(self, station, user=False, idempotency_key=False, request_hash=False):
        self.ensure_one()
        Tx = self.env['acpec.fuel.transaction'].sudo()
        # Check idempotency before locking
        if idempotency_key:
            existing = Tx.search([
                ('transaction_type', '=', 'consommation_station'),
                ('qr_id', '=', self.id),
                ('idempotency_key', '=', idempotency_key),
            ], limit=1)
            if existing:
                if existing.request_hash and request_hash and existing.request_hash != request_hash:
                    raise ValidationError(_('idempotency_conflict: même idempotency_key avec payload différent.'))
                return existing
        with self.env.cr.savepoint():
            # Lock the QR
            self._lock_records()
            self.invalidate_recordset()
            # Check idempotency again after locking
            if idempotency_key:
                existing = Tx.search([
                    ('transaction_type', '=', 'consommation_station'),
                    ('qr_id', '=', self.id),
                    ('idempotency_key', '=', idempotency_key),
                ], limit=1)
                if existing:
                    return existing
            # Validate QR state
            if self.state != 'active':
                raise UserError(_('Le QR n’est pas actif et ne peut pas être consommé.'))
            if self.company_id != station.company_id:
                raise UserError(_('La station et le QR n’appartiennent pas à la même société.'))
            self.action_refresh_expiration_state()
            self.invalidate_recordset()
            if self.state == 'blocked':
                raise UserError(_('QR bloqué : séparation requise.'))
            if self.state == 'expired':
                raise UserError(_('Le QR est expiré.'))
            # Process consumption
            tx_lines = []
            for line in self.line_ids.filtered(lambda l: l.state == 'active'):
                line.face_line_id.write({
                    'qty_qr_active': line.face_line_id.qty_qr_active - line.qty,
                    'qty_consumed': line.face_line_id.qty_consumed + line.qty,
                })
                line.write({'state': 'consumed'})
                tx_lines.append(line._transaction_line_vals())
            self.write({
                'state': 'consumed',
                'consumed_station_id': station.id,
                'consumed_user_id': user.id if user else self.env.user.id,
                'consumed_at': fields.Datetime.now(),
            })
            return Tx.log(
                'consommation_station', self.company_id,
                wallet=self.wallet_id, qr=self, station=station,
                lines=tx_lines, idempotency_key=idempotency_key, request_hash=request_hash
            )

    def action_retirer_to_child(self, lines, idempotency_key=False, request_hash=False):
        self.ensure_one()
        Tx = self.env['acpec.fuel.transaction'].sudo()
        if idempotency_key:
            existing = Tx.search([
                ('transaction_type', '=', 'retirer_qr'),
                ('parent_qr_id', '=', self.id),
                ('idempotency_key', '=', idempotency_key),
            ], limit=1)
            if existing and existing.qr_id:
                if existing.request_hash and request_hash and existing.request_hash != request_hash:
                    raise ValidationError(_('idempotency_conflict: même idempotency_key avec payload différent.'))
                return existing.qr_id

        if not lines:
            raise ValidationError(_('Au moins une ligne doit etre retiree du QR.'))

        requested = {}
        for item in lines:
            qr_line_id = int(item.get('qr_line_id') or 0)
            qty = int(item.get('qty') or 0)
            if qr_line_id <= 0:
                raise ValidationError(_("Parametre 'qr_line_id' invalide ou manquant."))
            if qty <= 0:
                raise ValidationError(_('La quantite a retirer doit etre positive.'))
            requested[qr_line_id] = requested.get(qr_line_id, 0) + qty

        with self.env.cr.savepoint():
            self._lock_records()
            self.invalidate_recordset(['state'])
            if idempotency_key:
                existing = Tx.search([
                    ('transaction_type', '=', 'retirer_qr'),
                    ('parent_qr_id', '=', self.id),
                    ('idempotency_key', '=', idempotency_key),
                ], limit=1)
                if existing and existing.qr_id:
                    return existing.qr_id

            if self.state != 'active':
                raise UserError(_('Seuls les QR actifs peuvent faire l objet d un retrait partiel.'))

            self.action_refresh_expiration_state()
            self.invalidate_recordset(['state'])
            if self.state != 'active':
                raise UserError(_('Le QR source doit rester actif pour retirer des tickets.'))

            self.env.cr.execute(
                'SELECT id FROM acpec_fuel_qr_line WHERE id IN %s FOR UPDATE',
                [tuple(requested.keys())],
            )
            source_lines = self.env['acpec.fuel.qr.line'].sudo().browse(list(requested.keys())).exists()
            source_by_id = {line.id: line for line in source_lines}

            qr_child = self.sudo().create({
                'wallet_id': self.wallet_id.id,
                'parent_id': self.id,
            })
            tx_lines = []

            for qr_line_id, qty in requested.items():
                src = source_by_id.get(qr_line_id)
                if not src or src.qr_id.id != self.id:
                    raise ValidationError(_('La ligne QR source ne fait pas partie du QR actif.'))
                if src.state != 'active':
                    raise ValidationError(_('Seules les lignes actives peuvent etre retirees.'))
                if qty > src.qty:
                    raise ValidationError(_('Quantite insuffisante sur la ligne QR source.'))

                if qty == src.qty:
                    src.write({'qr_id': qr_child.id})
                    moved_line = src
                else:
                    src.write({'qty': src.qty - qty})
                    moved_line = self.env['acpec.fuel.qr.line'].sudo().create({
                        'qr_id': qr_child.id,
                        'source_qr_line_id': src.id,
                        'face_line_id': src.face_line_id.id,
                        'purchase_id': src.purchase_id.id,
                        'purchase_line_id': src.purchase_line_id.id,
                        'face_value': src.face_value,
                        'qty': qty,
                        'state': 'active',
                        'expires_at': src.expires_at,
                    })
                tx_lines.append(moved_line._transaction_line_vals())

            self.invalidate_recordset()
            qr_child.invalidate_recordset()
            if not qr_child.line_ids:
                raise ValidationError(_('Le nouveau QR doit contenir au moins une ligne.'))
            if not self.line_ids.filtered(lambda line: line.state == 'active'):
                raise ValidationError(_('Le QR source doit conserver au moins une ligne active.'))

            self._set_state_from_lines()
            qr_child._set_state_from_lines()
            Tx.log(
                'retirer_qr',
                self.company_id,
                wallet=self.wallet_id,
                qr=qr_child,
                parent_qr=self,
                lines=tx_lines,
                idempotency_key=idempotency_key,
                request_hash=request_hash,
                note=_('Retrait partiel de tickets vers un nouveau QR.'),
            )
            return qr_child

    def action_separer_valid_to_child(self, idempotency_key=False, request_hash=False):
        self.ensure_one()
        Tx = self.env['acpec.fuel.transaction'].sudo()
        if idempotency_key:
            existing = Tx.search([
                ('transaction_type', '=', 'separer_qr'),
                ('parent_qr_id', '=', self.id),
                ('idempotency_key', '=', idempotency_key),
            ], limit=1)
            if existing and existing.qr_id:
                if existing.request_hash and request_hash and existing.request_hash != request_hash:
                    raise ValidationError(_('idempotency_conflict: même idempotency_key avec payload différent.'))
                return existing.qr_id

        with self.env.cr.savepoint():
            self._lock_records()
            self.invalidate_recordset(['state'])
            if idempotency_key:
                existing = Tx.search([
                    ('transaction_type', '=', 'separer_qr'),
                    ('parent_qr_id', '=', self.id),
                    ('idempotency_key', '=', idempotency_key),
                ], limit=1)
                if existing and existing.qr_id:
                    return existing.qr_id

            if self.state != 'blocked':
                raise UserError(_('Seuls les QR partiellement expires peuvent etre separes.'))

            self.action_refresh_expiration_state()
            self.invalidate_recordset(['state'])
            if self.state != 'blocked':
                raise UserError(_('Le QR source ne contient pas de partie non expiree separable.'))

            now = fields.Datetime.now()
            expired_lines = self.line_ids.filtered(
                lambda line: line.state == 'expired' or (line.expires_at and line.expires_at <= now)
            )
            valid_lines = self.line_ids.filtered(
                lambda line: line.state in ('active', 'blocked')
                and (not line.expires_at or line.expires_at > now)
            )
            if not expired_lines:
                raise ValidationError(_('Le QR source ne contient aucune ligne expiree a separer.'))
            if not valid_lines:
                raise ValidationError(_('Le QR source ne contient aucune ligne non expiree a separer.'))

            self.env.cr.execute(
                'SELECT id FROM acpec_fuel_qr_line WHERE id IN %s FOR UPDATE',
                [tuple(valid_lines.ids)],
            )

            qr_child = self.sudo().create({
                'wallet_id': self.wallet_id.id,
                'parent_id': self.id,
            })
            tx_lines = []
            for line in valid_lines:
                if line.state == 'blocked':
                    line.face_line_id.write({
                        'qty_qr_blocked': line.face_line_id.qty_qr_blocked - line.qty,
                        'qty_qr_active': line.face_line_id.qty_qr_active + line.qty,
                    })
                line.write({
                    'qr_id': qr_child.id,
                    'state': 'active',
                })
                tx_lines.append(line._transaction_line_vals())

            self.invalidate_recordset()
            qr_child.invalidate_recordset()
            if not qr_child.line_ids.filtered(lambda line: line.state == 'active'):
                raise ValidationError(_('Le nouveau QR doit contenir au moins une ligne non expiree.'))
            if not self.line_ids.filtered(lambda line: line.state == 'expired'):
                raise ValidationError(_('Le QR source doit conserver les lignes expirees.'))

            self._set_state_from_lines()
            qr_child._set_state_from_lines()
            Tx.log(
                'separer_qr',
                self.company_id,
                wallet=self.wallet_id,
                qr=qr_child,
                parent_qr=self,
                lines=tx_lines,
                idempotency_key=idempotency_key,
                request_hash=request_hash,
                note=_('Separation des tickets non expires vers un nouveau QR.'),
            )
            return qr_child

    def _set_state_from_lines(self):
        for qr in self:
            states = set(qr.line_ids.mapped('state'))
            if states == {'expired'}:
                qr.state = 'expired'
            elif 'expired' in states and (states - {'expired'}):
                qr.state = 'blocked'
                for line in qr.line_ids.filtered(lambda l: l.state == 'active'):
                    line.write({'state': 'blocked'})
                    line.face_line_id.write({
                        'qty_qr_active': line.face_line_id.qty_qr_active - line.qty,
                        'qty_qr_blocked': line.face_line_id.qty_qr_blocked + line.qty,
                    })
            elif 'blocked' in states and 'active' in states:
                qr.state = 'blocked'
                # Ne traiter QUE les lignes active pour éviter le double-comptage des blocked
                for line in qr.line_ids.filtered(lambda l: l.state == 'active'):
                    line.write({'state': 'blocked'})
                    line.face_line_id.write({
                        'qty_qr_active': line.face_line_id.qty_qr_active - line.qty,
                        'qty_qr_blocked': line.face_line_id.qty_qr_blocked + line.qty,
                    })
            elif 'blocked' in states:
                qr.state = 'blocked'
            else:
                qr.state = 'active'


    @api.model
    def _cron_process_expiration(self):
        now = fields.Datetime.now()
        face_lines = self.env['acpec.fuel.face.line'].sudo().search([('qty_available', '>', 0), ('expires_at', '!=', False), ('expires_at', '<=', now)])
        for line in face_lines:
            qty = line.qty_available
            line.move_available_to_expired()
            self.env['acpec.fuel.transaction'].log('expiration_faces', line.company_id, wallet=line.wallet_id, purchase=line.purchase_id, lines=[{
                'purchase_id': line.purchase_id.id,
                'purchase_line_id': line.purchase_line_id.id,
                'face_line_id': line.id,
                'face_value': line.face_value,
                'qty': qty,
            }], note=_('Expiration de tickets disponibles.'))
        qrs = self.sudo().search([('state', 'in', ['active', 'blocked'])])
        for qr in qrs:
            try:
                with self.env.cr.savepoint():
                    qr._lock_records()
                    qr.invalidate_recordset()
                    qr.action_refresh_expiration_state()
            except Exception:
                _logger.exception("Expiration QR %s failed", qr.id)
                continue


class AcpecFuelQrLine(models.Model):
    _name = 'acpec.fuel.qr.line'
    _description = 'Ligne Bon de retrait'
    _order = 'qr_id, id'

    qr_id = fields.Many2one('acpec.fuel.qr', string='QR', required=True, ondelete='cascade', index=True)
    source_qr_line_id = fields.Many2one('acpec.fuel.qr.line', string='Ligne source split', index=True)
    face_line_id = fields.Many2one('acpec.fuel.face.line', string='Carnet', required=True, index=True, ondelete='restrict')
    purchase_id = fields.Many2one('acpec.fuel.purchase', string='Lot d’achat', required=True, index=True)
    purchase_line_id = fields.Many2one('acpec.fuel.purchase.line', string='Ligne d’achat', required=True, index=True)
    company_id = fields.Many2one('res.company', related='qr_id.company_id', store=True, readonly=True)
    currency_id = fields.Many2one('res.currency', related='qr_id.currency_id', store=True, readonly=True)
    face_value = fields.Monetary(string='Valeur de face', required=True)
    qty = fields.Integer(string='Quantité', required=True)
    amount = fields.Monetary(string='Montant', compute='_compute_amount', store=True)
    state = fields.Selection([
        ('active', 'Actif'),
        ('blocked', 'Bloqué'),
        ('split', 'Splitté'),
        ('consumed', 'Consommé'),
        ('expired', 'Expiré'),
    ], string='État', default='active', index=True)
    expires_at = fields.Datetime(string='Expiration')

    @api.depends('face_value', 'qty')
    def _compute_amount(self):
        for rec in self:
            rec.amount = rec.face_value * rec.qty

    @api.constrains('qty', 'face_value')
    def _check_values(self):
        for rec in self:
            if rec.qty <= 0:
                raise ValidationError(_('La quantité d’une ligne QR doit être positive.'))
            if rec.face_value <= 0:
                raise ValidationError(_('La valeur de face doit être positive.'))

    def _transaction_line_vals(self):
        self.ensure_one()
        return {
            'purchase_id': self.purchase_id.id,
            'purchase_line_id': self.purchase_line_id.id,
            'face_line_id': self.face_line_id.id,
            'qr_id': self.qr_id.id,
            'qr_line_id': self.id,
            'face_value': self.face_value,
            'qty': self.qty,
        }
