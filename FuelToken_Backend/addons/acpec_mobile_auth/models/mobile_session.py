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
        ('pending_trust', 'Pending Trust'),
        ('trusted', 'Trusted'),
        ('blocked', 'Blocked'),
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

    @api.model_create_multi
    def create(self, vals_list):
        sequence = self.env['ir.sequence']
        for vals in vals_list:
            if vals.get('name', 'New') == 'New':
                vals['name'] = sequence.next_by_code('acpec.mobile.session') or 'New'
        return super().create(vals_list)

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
        if mobile_state != 'approved':
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
        value = self.env['ir.config_parameter'].sudo().get_param(
            'acpec_mobile_auth.refresh_token_grace_seconds',
            default='30',
        )
        try:
            seconds = int(value)
        except (TypeError, ValueError):
            seconds = 30
        return max(0, min(seconds, 120))

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
                body='Device mobile marqué trusted par %s. Device UID: %s'
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
                body='Confiance device réinitialisée par %s. Device UID: %s'
                % (self.env.user.display_name, session.device_uid or 'n/a')
            )
        return True

    def unlink(self):
        raise UserError(_('Les sessions mobiles doivent être révoquées et non supprimées.'))
