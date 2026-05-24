from odoo import api, fields, models, _
from odoo.exceptions import ValidationError, UserError


class AcpecFuelQr(models.Model):
    _name = 'acpec.fuel.qr'
    _description = 'QR FuelToken'
    _inherit = ['mail.thread', 'mail.activity.mixin', 'acpec.fuel.public.code.mixin']
    _order = 'id desc'

    name = fields.Char(string='Référence interne', default='New', readonly=True, copy=False)
    wallet_id = fields.Many2one('acpec.fuel.wallet', string='Compte FuelToken', required=True, index=True)
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
    split_idempotency_key = fields.Char(string='Cle idempotence split', index=True, copy=False)

    _public_code_unique = models.Constraint(
        'UNIQUE(public_code)',
        'Le code public du QR doit etre unique.',
    )
    _idempotency_wallet_unique = models.Constraint(
        'UNIQUE(wallet_id, idempotency_key)',
        'Cette operation QR existe deja pour ce compte.',
    )
    _split_idempotency_unique = models.Constraint(
        'UNIQUE(split_idempotency_key)',
        'Cette operation de split a deja ete enregistree.',
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
    def issue_from_available(self, wallet, requests, idempotency_key=False):
        if idempotency_key:
            existing = self.sudo().search([('wallet_id', '=', wallet.id), ('idempotency_key', '=', idempotency_key)], limit=1)
            if existing:
                return existing
        with self.env.cr.savepoint():
            qr = self.sudo().create({'wallet_id': wallet.id, 'idempotency_key': idempotency_key or False})
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

    def action_consume_by_station(self, station, user=False, idempotency_key=False):
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
                raise UserError(_('QR bloqué : split requis.'))
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
                lines=tx_lines, idempotency_key=idempotency_key
            )

    def action_split(self, children, idempotency_key=False):
        self.ensure_one()
        if idempotency_key and self.split_idempotency_key == idempotency_key and self.child_ids:
            return self.child_ids
        with self.env.cr.savepoint():
            self._lock_records()
            self.invalidate_recordset(['state', 'split_idempotency_key'])
            if idempotency_key and self.split_idempotency_key == idempotency_key and self.child_ids:
                return self.child_ids
            if self.state not in ('active', 'blocked'):
                raise UserError(_('Seuls les QR actifs ou bloqués peuvent être splittés.'))
            if self.state == 'blocked':
                for child in children:
                    for item in child.get('lines') or []:
                        if not item.get('qr_line_id'):
                            raise ValidationError(_(
                                'Pour un QR bloque, chaque ligne de split doit reference qr_line_id.'
                            ))
            source_lines = self.line_ids.filtered(lambda l: l.state in ('active', 'blocked', 'expired')).sorted(
                lambda l: (l.face_value, l.expires_at or fields.Datetime.to_datetime('9999-12-31 00:00:00'), l.id)
            )
            if not source_lines:
                raise ValidationError(_('Le QR parent ne contient aucune ligne à répartir.'))
            total_by_value = {}
            requested_by_value = {}
            source_by_id = {line.id: line for line in source_lines}
            for line in source_lines:
                total_by_value[line.face_value] = total_by_value.get(line.face_value, 0) + line.qty
            for child in children:
                if not child.get('lines'):
                    raise ValidationError(_('Chaque QR enfant doit contenir au moins une ligne.'))
                for item in child.get('lines') or []:
                    source_line_id = int(item.get('qr_line_id') or 0)
                    if source_line_id:
                        source_line = source_by_id.get(source_line_id)
                        if not source_line:
                            raise ValidationError(_('La ligne QR source ne fait pas partie du QR parent.'))
                        value = source_line.face_value
                    else:
                        value = float(item.get('face_value'))
                    qty = int(item.get('qty') or 0)
                    if qty <= 0:
                        raise ValidationError(_('Chaque ligne de split doit avoir une quantité positive.'))
                    requested_by_value[value] = requested_by_value.get(value, 0) + qty
            if total_by_value != requested_by_value:
                raise ValidationError(_('Le split doit répartir exactement toutes les faces du QR parent par valeur de face.'))
            children_qrs = self.env['acpec.fuel.qr']
            pool = []
            for line in source_lines:
                pool.append({'line': line, 'remaining': line.qty})
            tx_lines = []
            for child_index, child in enumerate(children, start=1):
                qr_child = self.sudo().create({
                    'wallet_id': self.wallet_id.id,
                    'parent_id': self.id,
                })
                for item in child.get('lines') or []:
                    source_line_id = int(item.get('qr_line_id') or 0)
                    value = False
                    if source_line_id:
                        source_line = source_by_id[source_line_id]
                        value = source_line.face_value
                    else:
                        value = float(item.get('face_value'))
                    remaining = int(item.get('qty') or 0)
                    for bucket in pool:
                        src = bucket['line']
                        if remaining <= 0:
                            break
                        if source_line_id and src.id != source_line_id:
                            continue
                        if not source_line_id and src.face_value != value:
                            continue
                        if bucket['remaining'] <= 0:
                            continue
                        qty = min(remaining, bucket['remaining'])
                        child_state = 'expired' if src.state == 'expired' else 'active'
                        if src.state == 'blocked':
                            src.face_line_id.write({
                                'qty_qr_blocked': src.face_line_id.qty_qr_blocked - qty,
                                'qty_qr_active': src.face_line_id.qty_qr_active + qty,
                            })
                        qr_line = self.env['acpec.fuel.qr.line'].sudo().create({
                            'qr_id': qr_child.id,
                            'source_qr_line_id': src.id,
                            'face_line_id': src.face_line_id.id,
                            'purchase_id': src.purchase_id.id,
                            'purchase_line_id': src.purchase_line_id.id,
                            'face_value': src.face_value,
                            'qty': qty,
                            'state': child_state,
                            'expires_at': src.expires_at,
                        })
                        tx_lines.append(qr_line._transaction_line_vals())
                        bucket['remaining'] -= qty
                        remaining -= qty
                    if remaining:
                        raise ValidationError(_('Quantité insuffisante dans le QR parent pour la face %s.') % value)
                qr_child._set_state_from_lines()
                children_qrs |= qr_child
            for bucket in pool:
                if bucket['remaining']:
                    raise ValidationError(_('Le split n’a pas réparti toutes les faces du QR parent.'))
            for line in self.line_ids:
                line.write({'state': 'split'})
            self.write({'state': 'split'})
            if idempotency_key:
                self.sudo().write({'split_idempotency_key': idempotency_key})
            self.env['acpec.fuel.transaction'].log('split_qr', self.company_id, wallet=self.wallet_id, parent_qr=self, lines=tx_lines, idempotency_key=idempotency_key)
            return children_qrs

    def action_retirer_to_child(self, lines, idempotency_key=False):
        self.ensure_one()
        Tx = self.env['acpec.fuel.transaction'].sudo()
        if idempotency_key:
            existing = Tx.search([
                ('transaction_type', '=', 'retirer_qr'),
                ('parent_qr_id', '=', self.id),
                ('idempotency_key', '=', idempotency_key),
            ], limit=1)
            if existing and existing.qr_id:
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
                note=_('Retrait partiel de tickets vers un nouveau QR.'),
            )
            return qr_child

    def action_separer_valid_to_child(self, idempotency_key=False):
        self.ensure_one()
        Tx = self.env['acpec.fuel.transaction'].sudo()
        if idempotency_key:
            existing = Tx.search([
                ('transaction_type', '=', 'separer_qr'),
                ('parent_qr_id', '=', self.id),
                ('idempotency_key', '=', idempotency_key),
            ], limit=1)
            if existing and existing.qr_id:
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
                note=_('Separation des tickets non expires vers un nouveau QR.'),
            )
            return qr_child

    def _set_state_from_lines(self):
        for qr in self:
            states = set(qr.line_ids.mapped('state'))
            if states == {'expired'}:
                qr.state = 'expired'
            elif 'expired' in states and 'active' in states:
                qr.state = 'blocked'
                for line in qr.line_ids.filtered(lambda l: l.state == 'active'):
                    line.write({'state': 'blocked'})
                    line.face_line_id.write({
                        'qty_qr_active': line.face_line_id.qty_qr_active - line.qty,
                        'qty_qr_blocked': line.face_line_id.qty_qr_blocked + line.qty,
                    })
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
            }], note=_('Expiration de faces disponibles.'))
        qrs = self.sudo().search([('state', 'in', ['active', 'blocked'])])
        qrs.action_refresh_expiration_state()


class AcpecFuelQrLine(models.Model):
    _name = 'acpec.fuel.qr.line'
    _description = 'Ligne QR FuelToken'
    _order = 'qr_id, id'

    qr_id = fields.Many2one('acpec.fuel.qr', string='QR', required=True, ondelete='cascade', index=True)
    source_qr_line_id = fields.Many2one('acpec.fuel.qr.line', string='Ligne source split', index=True)
    face_line_id = fields.Many2one('acpec.fuel.face.line', string='Ligne de faces', required=True, index=True, ondelete='restrict')
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
