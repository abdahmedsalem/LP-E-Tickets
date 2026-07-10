import hashlib
import hmac
import logging
import re
import secrets

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
    consumed_partner_id = fields.Many2one(
        'res.partner',
        string='Partenaire agent station',
        readonly=True,
        copy=False,
        index=True,
        help="Partenaire métier de l'agent station qui a consommé le QR. Sert au périmètre station agent ; le propriétaire du QR reste le partenaire du wallet du QR.",
    )
    consumed_at = fields.Datetime(string='Date consommation', readonly=True)
    expires_at = fields.Datetime(string='Expiration', compute='_compute_totals', store=True)
    amount_total = fields.Monetary(string='Montant', compute='_compute_totals', store=True)
    face_qty_total = fields.Integer(string='Nombre total de tickets', compute='_compute_totals', store=True)
    idempotency_key = fields.Char(string='Clé idempotence', index=True, copy=False)
    request_hash = fields.Char(string='Hash requête idempotence', index=True, copy=False)
    qr_numeric_code_hash = fields.Char(
        string='Empreinte du Code QR numérique',
        readonly=True,
        copy=False,
        index=True,
    )
    qr_numeric_code_nonce = fields.Char(
        string='Paramètre interne du Code QR numérique',
        readonly=True,
        copy=False,
    )

    _public_code_unique = models.Constraint(
        'UNIQUE(public_code)',
        'Le code public du QR doit etre unique.',
    )
    _qr_numeric_code_hash_unique = models.Constraint(
        'UNIQUE(qr_numeric_code_hash)',
        'Le Code QR numérique doit etre unique.',
    )
    _idempotency_wallet_unique = models.Constraint(
        'UNIQUE(wallet_id, idempotency_key)',
        'Cette operation QR existe deja pour ce compte.',
    )
    QR_NUMERIC_CODE_DIGITS = 12
    QR_NUMERIC_CODE_GROUP_SIZE = 4
    QR_NUMERIC_SECRET_MODEL = 'acpec.fueltoken.security.settings'
    _qr_economic_identity_fields = frozenset((
        'name',
        'wallet_id',
        'parent_id',
        'idempotency_key',
        'request_hash',
        'public_code',
        'qr_numeric_code_hash',
        'qr_numeric_code_nonce',
    ))
    _qr_controlled_state_fields = frozenset((
        'state',
        'consumed_station_id',
        'consumed_user_id',
        'consumed_partner_id',
        'consumed_at',
    ))


    def _is_qr_manual_code_label(self, value):
        value = str(value or '').strip()
        parts = value.split('-')
        return (
            len(parts) == 3
            and all(len(part) == 4 and part.isdigit() for part in parts)
        )

    @api.constrains('name')
    def _check_name_is_not_qr_manual_code(self):
        for rec in self:
            if rec._is_qr_manual_code_label(rec.name):
                raise ValidationError(
                    _('La référence QR ne peut pas être le code manuel.')
                )

    @api.model
    def _qr_numeric_code_settings(self):
        return self.env[self.QR_NUMERIC_SECRET_MODEL].sudo()._get_or_create_for_fueltoken_company()

    @api.model
    def _qr_numeric_code_secret(self):
        return self._qr_numeric_code_settings()._ensure_qr_numeric_secret()

    @api.model
    def _normalize_qr_numeric_code(self, code):
        digits = re.sub(r'\D', '', str(code or ''))
        if len(digits) != self.QR_NUMERIC_CODE_DIGITS:
            return False
        return digits

    @api.model
    def _format_qr_numeric_code(self, code):
        digits = self._normalize_qr_numeric_code(code)
        if not digits:
            return False
        size = self.QR_NUMERIC_CODE_GROUP_SIZE
        return '-'.join(digits[index:index + size] for index in range(0, len(digits), size))

    @api.model
    def _new_qr_numeric_code_nonce(self):
        return secrets.token_hex(8)

    @api.model
    def _derive_qr_numeric_code_digits(self, public_code, nonce=False):
        public_code = str(public_code or '').strip()
        nonce = str(nonce or '').strip()
        if not public_code:
            return False
        secret = self._qr_numeric_code_secret().encode('utf-8')
        raw = ('qr_numeric_code:%s:%s' % (public_code, nonce)).encode('utf-8')
        digest = hmac.new(secret, raw, hashlib.sha256).hexdigest()
        number = int(digest, 16) % (10 ** self.QR_NUMERIC_CODE_DIGITS)
        return ('%%0%sd' % self.QR_NUMERIC_CODE_DIGITS) % number

    @api.model
    def _hash_qr_numeric_code(self, code):
        digits = self._normalize_qr_numeric_code(code)
        if not digits:
            return False
        secret = self._qr_numeric_code_secret().encode('utf-8')
        raw = ('qr_numeric_code_hash:%s' % digits).encode('utf-8')
        return hmac.new(secret, raw, hashlib.sha256).hexdigest()

    def _qr_numeric_code_display(self):
        self.ensure_one()
        if not self.qr_numeric_code_nonce or not self.qr_numeric_code_hash:
            self._ensure_qr_numeric_code_hash()
            self.invalidate_recordset(['qr_numeric_code_nonce', 'qr_numeric_code_hash'])
        digits = self._derive_qr_numeric_code_digits(self.public_code, self.qr_numeric_code_nonce)
        return self._format_qr_numeric_code(digits)

    @api.model
    def _build_unique_qr_numeric_code_values(self, public_code, exclude_id=False):
        public_code = str(public_code or '').strip()
        if not public_code:
            return False, False
        for _attempt in range(40):
            nonce = self._new_qr_numeric_code_nonce()
            digits = self._derive_qr_numeric_code_digits(public_code, nonce)
            code_hash = self._hash_qr_numeric_code(digits)
            if not code_hash:
                continue
            domain = [('qr_numeric_code_hash', '=', code_hash)]
            if exclude_id:
                domain.append(('id', '!=', exclude_id))
            if not self.sudo().search(domain, limit=1):
                return nonce, code_hash
        raise ValidationError(_('Impossible de générer un Code QR numérique unique.'))

    def _ensure_qr_numeric_code_hash(self):
        for qr in self:
            if not qr.public_code:
                continue
            if qr.qr_numeric_code_hash and qr.qr_numeric_code_nonce:
                continue
            nonce, code_hash = qr._build_unique_qr_numeric_code_values(qr.public_code, exclude_id=qr.id)
            if code_hash:
                qr.with_context(allow_fuel_qr_economic_update=True).sudo().write({
                    'qr_numeric_code_nonce': nonce,
                    'qr_numeric_code_hash': code_hash,
                })
        return True

    @api.model
    def resolve_qr_reference(self, public_code=False, qr_numeric_code=False):
        public_code = str(public_code or '').strip()
        qr_numeric_code = str(qr_numeric_code or '').strip()

        if bool(public_code) == bool(qr_numeric_code):
            raise ValidationError(_('Transmettre soit le QR graphique, soit le Code QR numérique, mais pas les deux.'))

        if public_code:
            return self.sudo().search([('public_code', '=', public_code)], limit=1)

        digits = self._normalize_qr_numeric_code(qr_numeric_code)
        if not digits:
            return self.browse()
        code_hash = self._hash_qr_numeric_code(digits)
        if not code_hash:
            return self.browse()
        return self.sudo().search([('qr_numeric_code_hash', '=', code_hash)], limit=1)

    @api.model_create_multi
    def create(self, vals_list):
        if not self.env.context.get('allow_fuel_qr_create'):
            raise UserError(_(
                'La création de QR est réservée aux flux métier internes contrôlés.'
            ))
        Sequence = self.env['ir.sequence'].sudo()
        for vals in vals_list:
            if not vals.get('public_code'):
                vals['public_code'] = self._create_unique_public_code(prefix='QR', size=24)
            if vals.get('public_code') and (not vals.get('qr_numeric_code_hash') or not vals.get('qr_numeric_code_nonce')):
                nonce, code_hash = self._build_unique_qr_numeric_code_values(vals['public_code'])
                vals['qr_numeric_code_nonce'] = nonce
                vals['qr_numeric_code_hash'] = code_hash
            if vals.get('name', 'New') == 'New' or self._is_qr_manual_code_label(vals.get('name')):
                vals['name'] = Sequence.next_by_code('acpec.fuel.qr') or 'New'
        return super().create(vals_list)

    def _check_qr_protected_write_vals(self, vals):
        protected = set(vals or {}) & (self._qr_economic_identity_fields | self._qr_controlled_state_fields)
        if not protected:
            return
        if self.env.context.get('allow_fuel_qr_economic_update'):
            return
        if self.env.context.get('allow_fuel_qr_state_update') and not (protected & self._qr_economic_identity_fields):
            return
        raise ValidationError(
            _('Modification directe interdite sur les champs contrôlés du QR : %s')
            % ', '.join(sorted(protected))
        )

    def write(self, vals):
        self._check_qr_protected_write_vals(vals)
        return super().write(vals)

    def unlink(self):
        if not self.env.context.get('allow_fuel_qr_unlink'):
            raise UserError(_(
                'Les QR ne peuvent pas être supprimés hors flux interne contrôlé.'
            ))
        return super().unlink()

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
            qr = self.sudo().with_context(allow_fuel_qr_create=True).create({'wallet_id': wallet.id, 'idempotency_key': idempotency_key or False, 'request_hash': request_hash or False})
            allocations = self.env['acpec.fuel.face.line'].sudo().reserve_available(wallet, requests)
            tx_lines = []
            for allocation in allocations:
                face_line = allocation['face_line']
                qty = allocation['qty']
                qr_line = self.env['acpec.fuel.qr.line'].sudo().with_context(allow_fuel_qr_line_create=True).create({
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
                line.face_line_id.with_context(allow_fuel_face_line_state_update=True).sudo().write({
                    'qty_qr_active': line.face_line_id.qty_qr_active - line.qty,
                    'qty_expired': line.face_line_id.qty_expired + line.qty,
                })
            elif line.state == 'blocked':
                line.face_line_id.with_context(allow_fuel_face_line_state_update=True).sudo().write({
                    'qty_qr_blocked': line.face_line_id.qty_qr_blocked - line.qty,
                    'qty_expired': line.face_line_id.qty_expired + line.qty,
                })
            line.with_context(allow_fuel_qr_line_state_update=True).sudo().write({'state': 'expired'})
            tx_lines.append(line._transaction_line_vals())
        for line in valid_lines.filtered(lambda l: l.state == 'active'):
            line.face_line_id.with_context(allow_fuel_face_line_state_update=True).sudo().write({
                'qty_qr_active': line.face_line_id.qty_qr_active - line.qty,
                'qty_qr_blocked': line.face_line_id.qty_qr_blocked + line.qty,
            })
            line.with_context(allow_fuel_qr_line_state_update=True).sudo().write({'state': 'blocked'})
        self.with_context(allow_fuel_qr_state_update=True).sudo().write({'state': 'blocked'})
        self.env['acpec.fuel.transaction'].log('blocage_qr', self.company_id, wallet=self.wallet_id, qr=self, lines=tx_lines, note=_('QR bloqué par expiration partielle.'))

    def _expire_all_lines(self, expired_lines):
        tx_lines = []
        for line in expired_lines:
            if line.state == 'active':
                line.face_line_id.with_context(allow_fuel_face_line_state_update=True).sudo().write({
                    'qty_qr_active': line.face_line_id.qty_qr_active - line.qty,
                    'qty_expired': line.face_line_id.qty_expired + line.qty,
                })
            elif line.state == 'blocked':
                line.face_line_id.with_context(allow_fuel_face_line_state_update=True).sudo().write({
                    'qty_qr_blocked': line.face_line_id.qty_qr_blocked - line.qty,
                    'qty_expired': line.face_line_id.qty_expired + line.qty,
                })
            line.with_context(allow_fuel_qr_line_state_update=True).sudo().write({'state': 'expired'})
            tx_lines.append(line._transaction_line_vals())
        self.with_context(allow_fuel_qr_state_update=True).sudo().write({'state': 'expired'})
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
            actor_user = user or self.env.user
            actor_user = self.env['res.users'].sudo().browse(
                actor_user.id if hasattr(actor_user, 'id') else int(actor_user or 0)
            ).exists()
            if not actor_user:
                raise UserError(_('Acteur station requis pour consommer le QR.'))
            actor_partner = actor_user.partner_id
            counterparty_partner = self.wallet_id.partner_id
            counterparty_user = Tx._single_user_for_partner(counterparty_partner)
            tx_lines = []
            for line in self.line_ids.filtered(lambda l: l.state == 'active'):
                line.face_line_id.with_context(allow_fuel_face_line_state_update=True).sudo().write({
                    'qty_qr_active': line.face_line_id.qty_qr_active - line.qty,
                    'qty_consumed': line.face_line_id.qty_consumed + line.qty,
                })
                line.with_context(allow_fuel_qr_line_state_update=True).sudo().write({'state': 'consumed'})
                tx_lines.append(line._transaction_line_vals())
            self.with_context(allow_fuel_qr_state_update=True).sudo().write({
                'state': 'consumed',
                'consumed_station_id': station.id,
                'consumed_user_id': actor_user.id,
                'consumed_partner_id': actor_partner.id if actor_partner else False,
                'consumed_at': fields.Datetime.now(),
            })
            return Tx.log(
                'consommation_station', self.company_id,
                wallet=self.wallet_id, qr=self, station=station,
                lines=tx_lines, idempotency_key=idempotency_key, request_hash=request_hash,
                actor_partner=actor_partner,
                counterparty_partner=counterparty_partner,
                counterparty_user=counterparty_user,
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
                raise ValidationError(_('Le nombre de tickets à retirer doit être positif.'))
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

            qr_child = self.sudo().with_context(allow_fuel_qr_create=True).create({
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
                    raise ValidationError(_('Nombre de tickets insuffisant sur la ligne QR source.'))

                if qty == src.qty:
                    src.with_context(allow_fuel_qr_line_state_update=True).sudo().write({'qr_id': qr_child.id})
                    moved_line = src
                else:
                    src.with_context(allow_fuel_qr_line_state_update=True).sudo().write({'qty': src.qty - qty})
                    moved_line = self.env['acpec.fuel.qr.line'].sudo().with_context(allow_fuel_qr_line_create=True).create({
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

            qr_child = self.sudo().with_context(allow_fuel_qr_create=True).create({
                'wallet_id': self.wallet_id.id,
                'parent_id': self.id,
            })
            tx_lines = []
            for line in valid_lines:
                if line.state == 'blocked':
                    line.face_line_id.with_context(allow_fuel_face_line_state_update=True).sudo().write({
                        'qty_qr_blocked': line.face_line_id.qty_qr_blocked - line.qty,
                        'qty_qr_active': line.face_line_id.qty_qr_active + line.qty,
                    })
                line.with_context(allow_fuel_qr_line_state_update=True).sudo().write({
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
                qr.with_context(allow_fuel_qr_state_update=True).sudo().write({'state': 'expired'})
            elif 'expired' in states and (states - {'expired'}):
                qr.with_context(allow_fuel_qr_state_update=True).sudo().write({'state': 'blocked'})
                for line in qr.line_ids.filtered(lambda l: l.state == 'active'):
                    line.with_context(allow_fuel_qr_line_state_update=True).sudo().write({'state': 'blocked'})
                    line.face_line_id.with_context(allow_fuel_face_line_state_update=True).sudo().write({
                        'qty_qr_active': line.face_line_id.qty_qr_active - line.qty,
                        'qty_qr_blocked': line.face_line_id.qty_qr_blocked + line.qty,
                    })
            elif 'blocked' in states and 'active' in states:
                qr.with_context(allow_fuel_qr_state_update=True).sudo().write({'state': 'blocked'})
                # Ne traiter QUE les lignes active pour éviter le double-comptage des blocked
                for line in qr.line_ids.filtered(lambda l: l.state == 'active'):
                    line.with_context(allow_fuel_qr_line_state_update=True).sudo().write({'state': 'blocked'})
                    line.face_line_id.with_context(allow_fuel_face_line_state_update=True).sudo().write({
                        'qty_qr_active': line.face_line_id.qty_qr_active - line.qty,
                        'qty_qr_blocked': line.face_line_id.qty_qr_blocked + line.qty,
                    })
            elif 'blocked' in states:
                qr.with_context(allow_fuel_qr_state_update=True).sudo().write({'state': 'blocked'})
            else:
                qr.with_context(allow_fuel_qr_state_update=True).sudo().write({'state': 'active'})


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
    face_value = fields.Monetary(string='Valeur du ticket', required=True)
    qty = fields.Integer(string='Tickets', required=True)
    amount = fields.Monetary(string='Montant', compute='_compute_amount', store=True)
    state = fields.Selection([
        ('active', 'Actif'),
        ('blocked', 'Bloqué'),
        ('split', 'Splitté'),
        ('consumed', 'Consommé'),
        ('expired', 'Expiré'),
    ], string='État', default='active', index=True)
    expires_at = fields.Datetime(string='Expiration')

    @api.model_create_multi
    def create(self, vals_list):
        if not self.env.context.get('allow_fuel_qr_line_create'):
            raise UserError(_(
                'La création de lignes QR est réservée aux flux métier internes contrôlés.'
            ))
        return super().create(vals_list)

    @api.depends('face_value', 'qty')
    def _compute_amount(self):
        for rec in self:
            rec.amount = rec.face_value * rec.qty

    @api.constrains('qty', 'face_value')
    def _check_values(self):
        for rec in self:
            if rec.qty <= 0:
                raise ValidationError(_('Le nombre de tickets d’une ligne QR doit être positif.'))
            if rec.face_value <= 0:
                raise ValidationError(_('La valeur du ticket doit être positive.'))

    _economic_identity_fields = frozenset((
        'source_qr_line_id',
        'face_line_id',
        'purchase_id',
        'purchase_line_id',
        'face_value',
        'expires_at',
    ))
    _controlled_state_fields = frozenset((
        'qr_id',
        'qty',
        'state',
    ))

    def _check_protected_write_vals(self, vals):
        protected = set(vals or {}) & (self._economic_identity_fields | self._controlled_state_fields)
        if not protected:
            return
        if self.env.context.get('allow_fuel_qr_line_economic_update'):
            return
        if self.env.context.get('allow_fuel_qr_line_state_update') and not (protected & self._economic_identity_fields):
            return
        raise ValidationError(
            _('Modification directe interdite sur les champs économiques de la ligne QR : %s')
            % ', '.join(sorted(protected))
        )

    def write(self, vals):
        self._check_protected_write_vals(vals)
        return super().write(vals)

    def unlink(self):
        if not self.env.context.get('allow_fuel_qr_line_unlink'):
            raise ValidationError(_('Les lignes QR ne doivent pas être supprimées directement.'))
        return super().unlink()

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
