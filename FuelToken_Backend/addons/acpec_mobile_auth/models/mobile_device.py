# -*- coding: utf-8 -*-
from odoo import _, SUPERUSER_ID, api, fields, models
from odoo.exceptions import AccessError, UserError, ValidationError


class AcpecMobileDevice(models.Model):
    _name = 'acpec.mobile.device'
    _description = 'ACPEC Mobile Device'
    _inherit = ['mail.thread', 'mail.activity.mixin']
    _order = 'last_seen_at desc, create_date desc, id desc'

    name = fields.Char(
        compute='_compute_name',
        store=True,
        readonly=True,
        index=True,
    )
    user_id = fields.Many2one(
        'res.users',
        required=True,
        index=True,
        ondelete='cascade',
    )
    partner_id = fields.Many2one(
        'res.partner',
        related='user_id.partner_id',
        store=True,
        readonly=True,
        index=True,
    )
    company_id = fields.Many2one(
        'res.company',
        related='user_id.company_id',
        store=True,
        readonly=True,
        index=True,
    )
    stable_device_uid = fields.Char(required=True, index=True, copy=False)
    device_name = fields.Char()
    platform = fields.Selection([
        ('android', 'Android'),
        ('ios', 'iOS'),
        ('web', 'Web'),
        ('other', 'Other'),
    ])
    app_version = fields.Char()
    trust_state = fields.Selection([
        ('pending_trust', 'En attente'),
        ('trusted', 'Approuvé'),
        ('blocked', 'Bloqué'),
    ], default='pending_trust', required=True, index=True, tracking=True)
    trusted_at = fields.Datetime(readonly=True, copy=False)
    trusted_by = fields.Many2one('res.users', readonly=True, copy=False)
    blocked_at = fields.Datetime(readonly=True, copy=False)
    blocked_by = fields.Many2one('res.users', readonly=True, copy=False)
    blocked_reason = fields.Text(copy=False)
    trust_note = fields.Text(copy=False)
    first_seen_at = fields.Datetime(readonly=True, copy=False)
    last_seen_at = fields.Datetime(readonly=True, copy=False, index=True)
    active = fields.Boolean(default=True, index=True)

    _unique_user_stable_device_uid = models.Constraint(
        'UNIQUE(user_id, stable_device_uid)',
        'Un utilisateur ne peut pas avoir deux fois le même device stable.',
    )

    @api.depends('user_id', 'user_id.name', 'stable_device_uid', 'device_name')
    def _compute_name(self):
        for device in self:
            user_label = device.user_id.display_name or device.user_id.login or _('Utilisateur mobile')
            device_label = device.device_name or device.stable_device_uid or _('Device')
            device.name = '%s - %s' % (user_label, device_label)

    @api.model
    def _is_stable_device_uid(self, stable_device_uid):
        value = (stable_device_uid or '').strip()
        if not value:
            return False
        return value not in (
            'flutter-android-local',
            'flutter-ios-local',
            'flutter-web-local',
            'web-local',
        )

    @api.model
    def _normalize_stable_device_uid_or_raise(self, stable_device_uid):
        stable_device_uid = (stable_device_uid or '').strip()
        if not self._is_stable_device_uid(stable_device_uid):
            raise ValidationError(_('Identifiant appareil mobile invalide.'))
        return stable_device_uid

    @api.constrains('stable_device_uid')
    def _check_stable_device_uid(self):
        for device in self:
            device._normalize_stable_device_uid_or_raise(device.stable_device_uid)

    @api.model_create_multi
    def create(self, vals_list):
        now = fields.Datetime.now()
        for vals in vals_list:
            vals['stable_device_uid'] = self._normalize_stable_device_uid_or_raise(
                vals.get('stable_device_uid')
            )
            vals.setdefault('first_seen_at', now)
            vals.setdefault('last_seen_at', now)
        devices = super().create(vals_list)
        devices._assert_single_trusted_device_per_user(devices.mapped('user_id').sudo())
        return devices

    def write(self, vals):
        vals = dict(vals)
        if 'stable_device_uid' in vals:
            vals['stable_device_uid'] = self._normalize_stable_device_uid_or_raise(
                vals.get('stable_device_uid')
            )
        users_before = self.mapped('user_id').sudo() if 'trust_state' in vals or 'user_id' in vals else self.env['res.users']
        result = super().write(vals)
        if 'trust_state' in vals or 'user_id' in vals:
            self._assert_single_trusted_device_per_user(
                (users_before | self.mapped('user_id').sudo()).exists()
            )
        return result

    def _check_device_trust_admin(self):
        if self.env.uid == SUPERUSER_ID:
            return True
        if not self.env.user.has_group('acpec_mobile_auth.group_mobile_auth_admin'):
            raise AccessError(_('Seul un administrateur Mobile Auth peut modifier la confiance device.'))
        return True

    def _check_single_trust_target_per_user(self):
        targets_by_user = {}
        for device in self:
            stable_device_uid = device._normalize_stable_device_uid_or_raise(device.stable_device_uid)
            user_id = device.user_id.id
            if not user_id:
                continue
            previous_uid = targets_by_user.get(user_id)
            if previous_uid and previous_uid != stable_device_uid:
                raise UserError(_(
                    "Impossible d'approuver plusieurs appareils différents "
                    "pour le même utilisateur en une seule action."
                ))
            targets_by_user[user_id] = stable_device_uid
        return True

    @api.model
    def _lock_device_trust_scope_for_users(self, users):
        user_ids = tuple(sorted(set(users.exists().ids)))
        if not user_ids:
            return True
        self.env.cr.execute(
            'SELECT id FROM %s WHERE user_id IN %%s FOR UPDATE' % self._table,
            [user_ids],
        )
        return True

    @api.model
    def _assert_single_trusted_device_per_user(self, users):
        Device = self.with_context(active_test=False).sudo()
        for user in users.exists():
            trusted_devices = Device.search([
                ('user_id', '=', user.id),
                ('trust_state', '=', 'trusted'),
            ])
            trusted_device_uids = {
                (device.stable_device_uid or '').strip()
                for device in trusted_devices
                if Device._is_stable_device_uid(device.stable_device_uid)
            }
            if len(trusted_device_uids) > 1:
                raise UserError(_(
                    "Un utilisateur mobile ne peut avoir qu'un seul appareil approuvé."
                ))
        return True

    def _reset_other_trusted_devices_for_user(self, user, stable_device_uid):
        stable_device_uid = (stable_device_uid or '').strip()
        if not user or not user.exists() or not self._is_stable_device_uid(stable_device_uid):
            return self.browse()

        previous_trusted = self.with_context(active_test=False).sudo().search([
            ('user_id', '=', user.id),
            ('trust_state', '=', 'trusted'),
            ('stable_device_uid', '!=', stable_device_uid),
        ])
        if previous_trusted:
            previous_trusted.write({
                'trust_state': 'pending_trust',
                'trusted_at': False,
                'trusted_by': False,
            })
            previous_trusted._sync_sessions_from_device()
        return previous_trusted

    def _session_trust_snapshot_vals(self):
        self.ensure_one()
        state = self.trust_state or 'pending_trust'
        if state not in ('trusted', 'blocked'):
            state = 'pending_trust'
        return {
            'device_id': self.id,
            'device_trust_state': state,
            'device_trusted_at': self.trusted_at if state == 'trusted' else False,
            'device_blocked_at': self.blocked_at if state == 'blocked' else False,
            'device_trust_note': self.trust_note or self.blocked_reason or False,
        }

    def _linked_sessions(self):
        self.ensure_one()
        if not self.user_id or not self.stable_device_uid:
            return self.env['acpec.mobile.session']
        return self.env['acpec.mobile.session'].sudo().search([
            '|',
            ('device_id', '=', self.id),
            '&',
            ('user_id', '=', self.user_id.id),
            ('device_uid', '=', self.stable_device_uid),
        ])

    def _sync_sessions_from_device(self):
        Session = self.env['acpec.mobile.session'].sudo()
        impacted_keys = set()
        for device in self.with_context(active_test=False).sudo():
            sessions = device._linked_sessions()
            if not sessions:
                continue
            vals = device._session_trust_snapshot_vals()
            if device.trust_state == 'blocked':
                active_sessions = sessions.filtered(lambda session: session.state == 'active')
                inactive_sessions = sessions - active_sessions
                if inactive_sessions:
                    inactive_sessions.with_context(skip_device_approval_candidate_sync=True).write(vals)
                if active_sessions:
                    block_vals = dict(vals)
                    block_vals.update({
                        'state': 'revoked',
                        'revoked_at': device.blocked_at or fields.Datetime.now(),
                    })
                    active_sessions.with_context(skip_device_approval_candidate_sync=True).write(block_vals)
            else:
                sessions.with_context(skip_device_approval_candidate_sync=True).write(vals)
            impacted_keys.add((device.user_id.id, device.stable_device_uid))

        if impacted_keys:
            Session._sync_device_approval_candidates(impacted_keys)
            Session._assert_single_trusted_device_per_user(self.mapped('user_id').sudo())
        return True

    def _source_session_chatter_suffix(self):
        source_session_id = self.env.context.get('acpec_mobile_source_session_id')
        if not source_session_id:
            return ''
        source_session = self.env['acpec.mobile.session'].sudo().browse(source_session_id).exists()
        if not source_session:
            return ''
        source_label = source_session.name or source_session.display_name or str(source_session.id)
        return '. Origine session: %s' % source_label


    def _check_device_can_be_trusted(self):
        for device in self:
            if device.trust_state == 'blocked':
                raise UserError(_(
                    "Un device mobile bloqué ne peut pas être approuvé directement. "
                    "Remettez-le d'abord en attente avec un motif, puis approuvez-le séparément."
                ))
            if device.user_id.mobile_state == 'blocked':
                raise UserError(_("Impossible d'approuver un device d'un utilisateur mobile bloqué."))
        return True

    def action_open_block_device_wizard(self):
        self.ensure_one()
        self._check_device_trust_admin()
        return {
            'type': 'ir.actions.act_window',
            'name': _("Bloquer le device"),
            'res_model': 'acpec.mobile.device.trust.wizard',
            'view_mode': 'form',
            'target': 'new',
            'context': {
                'default_device_id': self.id,
                'default_operation': 'block',
            },
        }

    def action_open_reset_device_trust_wizard(self):
        self.ensure_one()
        self._check_device_trust_admin()
        return {
            'type': 'ir.actions.act_window',
            'name': _("Remettre le device en attente"),
            'res_model': 'acpec.mobile.device.trust.wizard',
            'view_mode': 'form',
            'target': 'new',
            'context': {
                'default_device_id': self.id,
                'default_operation': 'reset',
            },
        }

    def _device_trust_reason_suffix(self, reason):
        reason = (reason or '').strip()
        if not reason:
            return ''
        return '. Motif: %s' % reason

    def action_trust_device(self):
        self._check_device_trust_admin()
        self._check_device_can_be_trusted()
        self._check_single_trust_target_per_user()
        self._lock_device_trust_scope_for_users(self.mapped('user_id').sudo())
        now = fields.Datetime.now()
        for device in self:
            stable_device_uid = device._normalize_stable_device_uid_or_raise(device.stable_device_uid)
            device._reset_other_trusted_devices_for_user(device.user_id.sudo(), stable_device_uid)
            device.write({
                'trust_state': 'trusted',
                'trusted_at': now,
                'trusted_by': self.env.uid,
                'blocked_at': False,
                'blocked_by': False,
                'blocked_reason': False,
            })
            device._sync_sessions_from_device()
            device._assert_single_trusted_device_per_user(device.user_id.sudo())
            device.message_post(
                body='Device mobile approuvé par %s. Device UID: %s%s'
                % (self.env.user.display_name, stable_device_uid, device._source_session_chatter_suffix())
            )
        return True

    def action_block_device(self, reason=None):
        self._check_device_trust_admin()
        now = fields.Datetime.now()
        for device in self:
            device.write({
                'trust_state': 'blocked',
                'trusted_at': False,
                'trusted_by': False,
                'blocked_at': now,
                'blocked_by': self.env.uid,
                'blocked_reason': (reason or '').strip() or False,
            })
            device._sync_sessions_from_device()
            device.message_post(
                body='Device mobile bloqué par %s. Device UID: %s%s%s'
                % (self.env.user.display_name, device.stable_device_uid or 'n/a', device._source_session_chatter_suffix(), device._device_trust_reason_suffix(reason))
            )
        return True

    def action_reset_device_trust(self, reason=None):
        self._check_device_trust_admin()
        reason = (reason or '').strip()
        for device in self:
            if device.trust_state == 'blocked' and not reason:
                raise UserError(_("Le motif est obligatoire pour remettre en attente un device bloqué."))
            device.write({
                'trust_state': 'pending_trust',
                'trusted_at': False,
                'trusted_by': False,
                'blocked_at': False,
                'blocked_by': False,
                'blocked_reason': False,
            })
            device._sync_sessions_from_device()
            device.message_post(
                body='Confiance device remise en attente par %s. Device UID: %s%s%s'
                % (self.env.user.display_name, device.stable_device_uid or 'n/a', device._source_session_chatter_suffix(), device._device_trust_reason_suffix(reason))
            )
        return True

    def unlink(self):
        raise UserError(_('Les devices mobiles doivent être archivés, bloqués ou réinitialisés, non supprimés.'))
