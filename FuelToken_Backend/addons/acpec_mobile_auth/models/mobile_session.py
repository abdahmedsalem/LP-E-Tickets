import hashlib
import secrets

from dateutil.relativedelta import relativedelta

from odoo import _, api, fields, models
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
    expires_at = fields.Datetime(required=True, index=True)
    refresh_expires_at = fields.Datetime(required=True, index=True)
    last_seen_at = fields.Datetime(readonly=True, copy=False)
    revoked_at = fields.Datetime(readonly=True, copy=False)
    state = fields.Selection([
        ('active', 'Active'),
        ('expired', 'Expired'),
        ('revoked', 'Revoked'),
    ], default='active', required=True, index=True, tracking=True)

    _sql_constraints = [
        ('access_token_hash_unique', 'unique(access_token_hash)', 'Access token hash must be unique.'),
        ('refresh_token_hash_unique', 'unique(refresh_token_hash)', 'Refresh token hash must be unique.'),
    ]

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
        value = self.env['ir.config_parameter'].sudo().get_param('acpec_mobile_auth.access_token_minutes')
        try:
            return int(value or 60)
        except Exception:
            return 60

    @api.model
    def _refresh_days(self):
        value = self.env['ir.config_parameter'].sudo().get_param('acpec_mobile_auth.refresh_token_days')
        try:
            return int(value or 30)
        except Exception:
            return 30

    @api.model
    def create_for_user(self, user, device_vals=None):
        if not user or not user.exists() or not user.active:
            raise AccessError(_('Utilisateur mobile invalide ou inactif.'))
        if getattr(user, 'mobile_state', False) == 'rejected':
            raise AccessError(_('Compte mobile rejeté.'))
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
            session.sudo().write({'state': 'expired'})
            return self.browse()
        if not session.user_id.active:
            session.sudo().write({'state': 'revoked', 'revoked_at': now})
            return self.browse()
        session.sudo().write({'last_seen_at': now})
        return session

    @api.model
    def refresh_with_token(self, refresh_token, device_vals=None):
        token_hash = self._hash_token(refresh_token)
        session = self.sudo().search([('refresh_token_hash', '=', token_hash)], limit=1)
        if not session:
            raise AccessError(_('Refresh token invalide.'))
        now = fields.Datetime.now()
        if session.state != 'active':
            raise AccessError(_('La session mobile n’est plus active.'))
        if session.refresh_expires_at and session.refresh_expires_at <= now:
            session.sudo().write({'state': 'expired'})
            raise AccessError(_('Refresh token expiré.'))
        if not session.user_id.active:
            session.sudo().write({'state': 'revoked', 'revoked_at': now})
            raise AccessError(_('Utilisateur mobile inactif.'))
        access_token = self._new_token()
        new_refresh_token = self._new_token()
        expires_at = now + relativedelta(minutes=self._access_minutes())
        refresh_expires_at = now + relativedelta(days=self._refresh_days())
        vals = {
            'access_token_hash': self._hash_token(access_token),
            'refresh_token_hash': self._hash_token(new_refresh_token),
            'expires_at': expires_at,
            'refresh_expires_at': refresh_expires_at,
            'last_seen_at': now,
            'state': 'active',
        }
        for key in ('device_uid', 'device_name', 'platform', 'app_version', 'ip_address', 'user_agent'):
            if device_vals and key in device_vals and device_vals.get(key):
                vals[key] = device_vals[key]
        session.sudo().write(vals)
        return {
            'session': session,
            'access_token': access_token,
            'refresh_token': new_refresh_token,
            'expires_at': fields.Datetime.to_string(expires_at),
            'refresh_expires_at': fields.Datetime.to_string(refresh_expires_at),
            'token_type': 'Bearer',
        }

    def action_revoke(self):
        now = fields.Datetime.now()
        for session in self:
            if session.state == 'active':
                session.write({'state': 'revoked', 'revoked_at': now})
        return True

    def unlink(self):
        raise UserError(_('Les sessions mobiles doivent être révoquées et non supprimées.'))
