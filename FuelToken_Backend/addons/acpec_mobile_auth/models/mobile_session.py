import hashlib
import secrets

from dateutil.relativedelta import relativedelta

from odoo import _, SUPERUSER_ID, api, fields, models
from odoo.exceptions import AccessError, UserError, ValidationError


class AcpecMobileSession(models.Model):
    _name = 'acpec.mobile.session'
    _description = 'ACPEC Mobile Session'
    _inherit = ['mail.thread', 'mail.activity.mixin']
    _order = 'create_date desc, id desc'

    name = fields.Char(default='New', readonly=True, copy=False, index=True)
    user_id = fields.Many2one('res.users', required=True, index=True, ondelete='cascade')
    partner_id = fields.Many2one('res.partner', related='user_id.partner_id', store=True, readonly=True, index=True)
    company_id = fields.Many2one('res.company', related='user_id.company_id', store=True, readonly=True, index=True)
    mobile_phone = fields.Char(
        string='Téléphone mobile',
        compute='_compute_mobile_identity_fields',
        store=True,
        readonly=True,
        index=True,
    )
    mobile_user_label = fields.Char(
        string='Utilisateur mobile',
        compute='_compute_mobile_identity_fields',
        store=True,
        readonly=True,
        index=True,
    )
    is_device_approval_candidate = fields.Boolean(
        string='Device à approuver',
        readonly=True,
        copy=False,
        index=True,
    )
    access_token_hash = fields.Char(required=True, index=True, copy=False)
    refresh_token_hash = fields.Char(required=True, index=True, copy=False)
    device_uid = fields.Char(index=True)
    device_name = fields.Char()
    platform = fields.Selection([
        ('android', 'Android'),
        ('ios', 'iOS'),
        ('web', 'Web'),
        ('other', 'Other'),
    ])
    app_version = fields.Char()
    ip_address = fields.Char()
    user_agent = fields.Char()
    device_trust_state = fields.Selection([
        ('pending_trust', 'En attente'),
        ('trusted', 'Approuvé'),
        ('blocked', 'Bloqué'),
    ], default='pending_trust', required=True, index=True, tracking=True)
    device_trusted_at = fields.Datetime(readonly=True, copy=False)
    device_blocked_at = fields.Datetime(readonly=True, copy=False)
    device_trust_note = fields.Text(copy=False)
    expires_at = fields.Datetime(required=True, index=True)
    refresh_expires_at = fields.Datetime(required=True, index=True)
    last_seen_at = fields.Datetime(readonly=True, copy=False)
    revoked_at = fields.Datetime(readonly=True, copy=False)
    rotated_at = fields.Datetime(readonly=True, copy=False)
    refresh_grace_until = fields.Datetime(readonly=True, copy=False, index=True)
    refresh_grace_used_at = fields.Datetime(readonly=True, copy=False)
    rotated_to_session_id = fields.Many2one(
        'acpec.mobile.session',
        readonly=True,
        copy=False,
        ondelete='set null',
    )
    state = fields.Selection([
        ('active', 'Active'),
        ('rotated', 'Rotated'),
        ('expired', 'Expired'),
        ('revoked', 'Revoked'),
    ], default='active', required=True, index=True, tracking=True)

    _access_token_hash_unique = models.Constraint(
        'UNIQUE(access_token_hash)',
        'Access token hash must be unique.',
    )
    _refresh_token_hash_unique = models.Constraint(
        'UNIQUE(refresh_token_hash)',
        'Refresh token hash must be unique.',
    )

    @api.depends(
        'user_id',
        'user_id.name',
        'user_id.login',
        'user_id.mobile_phone',
        'user_id.phone',
        'user_id.partner_id',
        'user_id.partner_id.name',
        'user_id.partner_id.phone',
    )
    def _compute_mobile_identity_fields(self):
        for session in self:
            user = session.user_id
            partner = user.partner_id if user else self.env['res.partner']
            login = (user.login or '').strip() if user else ''

            mobile_phone = (
                user.mobile_phone
                or user.phone
                or partner.phone
                or (login if login.isdigit() else False)
            ) if user else False

            user_name = (
                user.name
                or partner.name
                or login
            ) if user else ''

            user_name = (user_name or '').strip()
            mobile_phone = (mobile_phone or '').strip()

            session.mobile_phone = mobile_phone or False

            if user_name and mobile_phone:
                session.mobile_user_label = '%s - %s' % (user_name, mobile_phone)
            else:
                session.mobile_user_label = user_name or mobile_phone or False

    @api.model
    def _device_approval_candidate_base_domain(self):
        return [
            ('device_trust_state', '=', 'pending_trust'),
            ('state', '=', 'active'),
            ('device_uid', '!=', False),
            ('device_uid', '!=', ''),
            ('user_id.mobile_only', '=', True),
            ('user_id.mobile_state', 'in', ['approved', 'self_registered']),
        ]

    def _device_approval_candidate_keys(self):
        keys = set()
        for session in self:
            if session.user_id and session.device_uid:
                keys.add((session.user_id.id, session.device_uid))
        return keys

    @api.model
    def _sync_device_approval_candidates(self, keys=None):
        Session = self.sudo()

        if keys is None:
            sessions = Session.search([
                ('device_uid', '!=', False),
                ('device_uid', '!=', ''),
                ('user_id', '!=', False),
            ])
            keys = sessions._device_approval_candidate_keys()

        keys = {key for key in (keys or set()) if key and key[0] and key[1]}

        for user_id, device_uid in keys:
            scoped_domain = [
                ('user_id', '=', user_id),
                ('device_uid', '=', device_uid),
            ]
            scoped = Session.search(scoped_domain)

            latest_active = Session.search(
                scoped_domain + [
                    ('state', '=', 'active'),
                    ('device_uid', '!=', False),
                    ('device_uid', '!=', ''),
                    ('user_id.mobile_only', '=', True),
                    ('user_id.mobile_state', 'in', ['approved', 'self_registered']),
                ],
                order='create_date desc, id desc',
                limit=1,
            )

            candidate = latest_active if (
                latest_active
                and latest_active.device_trust_state == 'pending_trust'
            ) else Session.browse()

            to_clear = scoped.filtered(
                lambda session: session.is_device_approval_candidate and session != candidate
            )
            if to_clear:
                to_clear.with_context(skip_device_approval_candidate_sync=True).write({
                    'is_device_approval_candidate': False,
                })

            if candidate and not candidate.is_device_approval_candidate:
                candidate.with_context(skip_device_approval_candidate_sync=True).write({
                    'is_device_approval_candidate': True,
                })

    @api.model_create_multi
    def create(self, vals_list):
        sequence = self.env['ir.sequence']
        for vals in vals_list:
            if vals.get('name', 'New') == 'New':
                vals['name'] = sequence.next_by_code('acpec.mobile.session') or 'New'
        sessions = super().create(vals_list)
        sessions._sync_device_approval_candidates(sessions._device_approval_candidate_keys())
        return sessions

    def write(self, vals):
        tracked_fields = {
            'user_id',
            'device_uid',
            'state',
            'device_trust_state',
        }
        should_sync = bool(tracked_fields.intersection(vals))
        keys_before = self._device_approval_candidate_keys() if should_sync else set()

        result = super().write(vals)

        if should_sync and not self.env.context.get('skip_device_approval_candidate_sync'):
            keys_after = self._device_approval_candidate_keys()
            self._sync_device_approval_candidates(keys_before | keys_after)

        return result

    @api.model
    def _hash_token(self, token):
        return hashlib.sha256((token or '').encode('utf-8')).hexdigest()

    @api.model
    def _new_token(self):
        return secrets.token_urlsafe(48)

    @api.model
    def _access_minutes(self):
        return self.env["acpec.mobile.security.policy"].sudo().access_token_minutes()

    @api.model
    def _refresh_days(self):
        return self.env["acpec.mobile.security.policy"].sudo().refresh_token_days()

    @api.model
    def _has_group_safe(self, user, xmlid):
        try:
            return user.has_group(xmlid)
        except Exception:
            return False

    @api.model
    def _check_mobile_only_user(self, user):
        if not user or not user.exists() or not user.active:
            raise AccessError(_('Utilisateur mobile invalide ou inactif.'))

        mobile_state = getattr(user, 'mobile_state', False)
        if mobile_state not in ('approved', 'self_registered'):
            if mobile_state == 'pending':
                raise AccessError(_('Compte mobile en attente d’approbation.'))
            if mobile_state == 'rejected':
                raise AccessError(_('Compte mobile rejeté.'))
            if mobile_state == 'blocked':
                raise AccessError(_('Compte mobile bloqué.'))
            raise AccessError(_('Compte mobile non approuvé.'))

        if not getattr(user, 'mobile_only', False):
            raise AccessError(_('Ce compte n’est pas un compte mobile-only FuelToken.'))

        required_xmlids = (
            'base.group_portal',
            'acpec_mobile_auth.group_mobile_auth_user',
        )
        forbidden_xmlids = (
            'base.group_user',
            'base.group_public',
            'acpec_mobile_auth.group_mobile_auth_admin',
            'acpec_fueltoken_base.group_fuel_admin',
        )

        for xmlid in required_xmlids:
            if not self._has_group_safe(user, xmlid):
                raise AccessError(_('Compte mobile FuelToken incomplet ou mal configuré.'))

        for xmlid in forbidden_xmlids:
            if self._has_group_safe(user, xmlid):
                raise AccessError(_('Ce compte n’est pas autorisé à utiliser l’application mobile FuelToken.'))

    @api.model
    def _is_stable_device_uid(self, device_uid):
        """Return True for Patch32C stable Flutter install identifiers.

        Legacy placeholders such as ``flutter-android-local`` are deliberately
        excluded because they do not identify a real installation.
        """
        value = (device_uid or '').strip()
        return bool(value and value.startswith('ft-'))

    @api.model
    def _rotate_prior_active_sessions_for_device_login(self, user, device_uid, new_session, now):
        """Rotate older active sessions for the same stable device.

        OTP login creates a fresh audited session line.  For stable Patch32C
        device identifiers, older active sessions for the same user/device must
        no longer remain active.  No refresh grace is granted here: this is an
        OTP login replacement, not a refresh-token race.
        """
        if not user or not user.exists() or not new_session or not new_session.exists():
            return self.browse()

        device_uid = (device_uid or '').strip()
        if not self._is_stable_device_uid(device_uid):
            return self.browse()

        prior_sessions = self.sudo().search([
            ('id', '!=', new_session.id),
            ('user_id', '=', user.id),
            ('device_uid', '=', device_uid),
            ('state', '=', 'active'),
        ])

        if prior_sessions:
            prior_sessions.with_context(skip_device_approval_candidate_sync=True).write({
                'state': 'rotated',
                'rotated_at': now,
                'rotated_to_session_id': new_session.id,
                'refresh_grace_until': False,
                'refresh_grace_used_at': False,
                'last_seen_at': now,
            })
            self._sync_device_approval_candidates({(user.id, device_uid)})

        return prior_sessions

    @api.model
    def create_for_user(self, user, device_vals=None):
        self._check_mobile_only_user(user)
        device_vals = device_vals or {}
        access_token = self._new_token()
        refresh_token = self._new_token()
        now = fields.Datetime.now()
        expires_at = now + relativedelta(minutes=self._access_minutes())
        refresh_expires_at = now + relativedelta(days=self._refresh_days())
        vals = {
            'user_id': user.id,
            'access_token_hash': self._hash_token(access_token),
            'refresh_token_hash': self._hash_token(refresh_token),
            'expires_at': expires_at,
            'refresh_expires_at': refresh_expires_at,
            'last_seen_at': now,
            'state': 'active',
            'device_uid': device_vals.get('device_uid') or False,
            'device_name': device_vals.get('device_name') or False,
            'platform': device_vals.get('platform') if device_vals.get('platform') in ('android', 'ios', 'web', 'other') else False,
            'app_version': device_vals.get('app_version') or False,
            'ip_address': device_vals.get('ip_address') or False,
            'user_agent': device_vals.get('user_agent') or False,
            'device_trust_state': 'pending_trust',
        }
        session = self.sudo().create(vals)
        self._rotate_prior_active_sessions_for_device_login(
            user.sudo(),
            session.device_uid,
            session,
            now,
        )
        return {
            'session': session,
            'access_token': access_token,
            'refresh_token': refresh_token,
            'expires_at': fields.Datetime.to_string(expires_at),
            'refresh_expires_at': fields.Datetime.to_string(refresh_expires_at),
            'token_type': 'Bearer',
        }

    @api.model
    def authenticate_access_token(self, token):
        token_hash = self._hash_token(token)
        session = self.sudo().search([('access_token_hash', '=', token_hash)], limit=1)
        if not session:
            return self.browse()
        now = fields.Datetime.now()
        if session.state != 'active':
            return self.browse()
        if session.expires_at and session.expires_at <= now:
            # L'access token est court. Son expiration ne doit pas expirer
            # la session longue tant que refresh_expires_at reste valide.
            return self.browse()
        try:
            self._check_mobile_only_user(session.user_id.sudo())
        except AccessError:
            session.sudo().write({'state': 'revoked', 'revoked_at': now})
            return self.browse()
        session.sudo().write({'last_seen_at': now})
        return session

    @api.model
    def _refresh_token_grace_seconds(self):
        return self.env["acpec.mobile.security.policy"].sudo().refresh_token_grace_seconds()

    @api.model
    def _refresh_successor_device_vals(self, session, device_vals=None):
        vals = {
            'device_uid': session.device_uid or False,
            'device_name': session.device_name or False,
            'platform': session.platform or False,
            'app_version': session.app_version or False,
            'ip_address': session.ip_address or False,
            'user_agent': session.user_agent or False,
        }
        for key in ('device_uid', 'device_name', 'platform', 'app_version', 'ip_address', 'user_agent'):
            if device_vals and key in device_vals and device_vals.get(key):
                vals[key] = device_vals[key]
        return vals

    @api.model
    def _create_refresh_successor_session(self, session, now, device_vals=None):
        access_token = self._new_token()
        new_refresh_token = self._new_token()
        expires_at = now + relativedelta(minutes=self._access_minutes())
        refresh_expires_at = now + relativedelta(days=self._refresh_days())

        successor_device_vals = self._refresh_successor_device_vals(session, device_vals=device_vals)
        old_device_uid = session.device_uid or False
        new_device_uid = successor_device_vals.get('device_uid') or False
        same_device = bool(old_device_uid and new_device_uid and old_device_uid == new_device_uid)

        if same_device:
            device_trust_state = session.device_trust_state or 'pending_trust'
            device_trusted_at = session.device_trusted_at if device_trust_state == 'trusted' else False
            device_blocked_at = session.device_blocked_at if device_trust_state == 'blocked' else False
        else:
            device_trust_state = 'pending_trust'
            device_trusted_at = False
            device_blocked_at = False

        vals = {
            'user_id': session.user_id.id,
            'access_token_hash': self._hash_token(access_token),
            'refresh_token_hash': self._hash_token(new_refresh_token),
            'expires_at': expires_at,
            'refresh_expires_at': refresh_expires_at,
            'last_seen_at': now,
            'state': 'active',
            'device_trust_state': device_trust_state,
            'device_trusted_at': device_trusted_at,
            'device_blocked_at': device_blocked_at,
            'device_trust_note': session.device_trust_note if same_device else False,
        }
        vals.update(successor_device_vals)

        new_session = self.sudo().create(vals)
        return {
            'session': new_session,
            'access_token': access_token,
            'refresh_token': new_refresh_token,
            'expires_at': fields.Datetime.to_string(expires_at),
            'refresh_expires_at': fields.Datetime.to_string(refresh_expires_at),
            'token_type': 'Bearer',
        }

    @api.model
    def _assert_refreshable_mobile_session(self, session, now):
        if session.refresh_expires_at and session.refresh_expires_at <= now:
            session.sudo().write({'state': 'expired'})
            raise AccessError(_('Refresh token expiré.'))
        try:
            self._check_mobile_only_user(session.user_id.sudo())
        except AccessError as exc:
            session.sudo().write({'state': 'revoked', 'revoked_at': now})
            raise exc

    @api.model
    def _refresh_active_session(self, session, now, device_vals=None):
        self._assert_refreshable_mobile_session(session, now)

        result = self._create_refresh_successor_session(session, now, device_vals=device_vals)
        grace_seconds = self._refresh_token_grace_seconds()
        grace_until = now + relativedelta(seconds=grace_seconds) if grace_seconds else now

        session.sudo().write({
            'state': 'rotated',
            'rotated_at': now,
            'refresh_grace_until': grace_until,
            'refresh_grace_used_at': False,
            'rotated_to_session_id': result['session'].id,
            'last_seen_at': now,
        })
        return result

    @api.model
    def _refresh_rotated_session_in_grace(self, session, now, device_vals=None):
        if session.refresh_grace_used_at:
            raise AccessError(_('Refresh token déjà consommé.'))
        if not session.refresh_grace_until or session.refresh_grace_until <= now:
            raise AccessError(_('Refresh token invalide.'))

        self._assert_refreshable_mobile_session(session, now)

        session.sudo().write({
            'refresh_grace_used_at': now,
            'last_seen_at': now,
        })
        return self._create_refresh_successor_session(session, now, device_vals=device_vals)

    @api.model
    def refresh_with_token(self, refresh_token, device_vals=None):
        token_hash = self._hash_token(refresh_token)
        session = self.sudo().search([('refresh_token_hash', '=', token_hash)], limit=1)
        if not session:
            raise AccessError(_('Refresh token invalide.'))

        now = fields.Datetime.now()

        if session.state == 'active':
            return self._refresh_active_session(session, now, device_vals=device_vals)

        if session.state == 'rotated':
            return self._refresh_rotated_session_in_grace(session, now, device_vals=device_vals)

        raise AccessError(_('La session mobile n’est plus active.'))

    def _check_device_trust_admin(self):
        if self.env.uid == SUPERUSER_ID:
            return True
        if not self.env.user.has_group('acpec_mobile_auth.group_mobile_auth_admin'):
            raise AccessError('Seul un administrateur Mobile Auth peut modifier la confiance device.')
        return True

    def action_revoke(self):
        self._check_device_trust_admin()
        now = fields.Datetime.now()
        for session in self:
            if session.state == 'active':
                session.write({'state': 'revoked', 'revoked_at': now})
                session.message_post(body='Session mobile révoquée par %s.' % (self.env.user.display_name,))
        return True

    def action_trust_device(self):
        self._check_device_trust_admin()
        now = fields.Datetime.now()
        for session in self:
            if not session.device_uid:
                raise UserError('Impossible de faire confiance à une session sans identifiant device.')
            session.write({
                'device_trust_state': 'trusted',
                'device_trusted_at': now,
                'device_blocked_at': False,
            })
            session.message_post(
                body='Device mobile approuvé par %s. Device UID: %s'
                % (self.env.user.display_name, session.device_uid)
            )
        return True

    def action_block_device(self):
        self._check_device_trust_admin()
        now = fields.Datetime.now()
        for session in self:
            session.write({
                'device_trust_state': 'blocked',
                'device_blocked_at': now,
            })
            session.message_post(
                body='Device mobile bloqué par %s. Device UID: %s'
                % (self.env.user.display_name, session.device_uid or 'n/a')
            )
        return True

    def action_reset_device_trust(self):
        self._check_device_trust_admin()
        for session in self:
            session.write({
                'device_trust_state': 'pending_trust',
                'device_trusted_at': False,
                'device_blocked_at': False,
            })
            session.message_post(
                body='Confiance device remise en attente par %s. Device UID: %s'
                % (self.env.user.display_name, session.device_uid or 'n/a')
            )
        return True

    def unlink(self):
        raise UserError(_('Les sessions mobiles doivent être révoquées et non supprimées.'))
