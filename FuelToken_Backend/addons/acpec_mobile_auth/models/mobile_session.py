import hashlib
import logging
import secrets

from dateutil.relativedelta import relativedelta
from psycopg2 import errors as pg_errors

from odoo import _, SUPERUSER_ID, api, fields, models
from odoo.exceptions import AccessError, UserError, ValidationError


_logger = logging.getLogger(__name__)


class AcpecMobileSession(models.Model):
    _name = 'acpec.mobile.session'
    _description = 'ACPEC Mobile Session'
    _inherit = ['mail.thread', 'mail.activity.mixin']
    _order = 'create_date desc, id desc'

    name = fields.Char(default='New', readonly=True, copy=False, index=True)
    user_id = fields.Many2one('res.users', required=True, index=True, ondelete='cascade')
    device_id = fields.Many2one(
        'acpec.mobile.device',
        string='Device mobile',
        index=True,
        copy=False,
        readonly=True,
        ondelete='restrict',
    )
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

    ACCESS_LAST_SEEN_TOUCH_MIN_SECONDS = 60
    # Patch43K6: throttle du touch presence sur acpec.mobile.device.
    DEVICE_LAST_SEEN_TOUCH_MIN_SECONDS = 60

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
    def _normalize_stable_device_uid_or_raise(self, device_uid):
        device_uid = (device_uid or '').strip()
        if not self._is_stable_device_uid(device_uid):
            raise ValidationError(_('Identifiant appareil mobile invalide.'))
        return device_uid

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
        now = fields.Datetime.now()
        for vals in vals_list:
            vals['device_uid'] = self._normalize_stable_device_uid_or_raise(vals.get('device_uid'))
            if vals.get('name', 'New') == 'New':
                vals['name'] = sequence.next_by_code('acpec.mobile.session') or 'New'

            if not vals.get('device_id') and vals.get('user_id') and vals.get('device_uid'):
                device = self._get_or_create_device_for_session(
                    self.env['res.users'].sudo().browse(vals.get('user_id')),
                    {
                        'device_uid': vals.get('device_uid'),
                        'device_name': vals.get('device_name'),
                        'platform': vals.get('platform'),
                        'app_version': vals.get('app_version'),
                    },
                    now=vals.get('last_seen_at') or now,
                )
                vals['device_id'] = device.id
                vals.update(self._device_trust_values_for_device(device))

        with self.env.cr.savepoint():
            sessions = super().create(vals_list)
            sessions._sync_device_approval_candidates(sessions._device_approval_candidate_keys())
            sessions._assert_single_trusted_device_per_user(sessions.mapped('user_id').sudo())
        return sessions

    def write(self, vals):
        if 'device_uid' in vals:
            vals = dict(vals)
            vals['device_uid'] = self._normalize_stable_device_uid_or_raise(vals.get('device_uid'))

        tracked_fields = {
            'user_id',
            'device_uid',
            'state',
            'device_trust_state',
        }
        should_sync = bool(tracked_fields.intersection(vals))
        should_assert_single_trusted = bool({
            'user_id',
            'device_uid',
            'device_trust_state',
        }.intersection(vals))
        keys_before = self._device_approval_candidate_keys() if should_sync else set()
        users_before = self.mapped('user_id').sudo() if should_assert_single_trusted else self.env['res.users']

        with self.env.cr.savepoint():
            result = super().write(vals)

            if should_sync and not self.env.context.get('skip_device_approval_candidate_sync'):
                keys_after = self._device_approval_candidate_keys()
                self._sync_device_approval_candidates(keys_before | keys_after)

            if should_assert_single_trusted:
                self._assert_single_trusted_device_per_user(
                    (users_before | self.mapped('user_id').sudo()).exists()
                )

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
        """Return True for a usable mobile installation identifier.

        The mobile app normally sends Patch32C identifiers prefixed with
        ``ft-``.  The backend cannot cryptographically attest that prefix in
        V1, but it can fail closed on absent values and known legacy/local
        placeholders that do not identify a real installation.
        """
        value = (device_uid or '').strip()
        if not value:
            return False
        return value not in (
            'flutter-android-local',
            'flutter-ios-local',
            'flutter-web-local',
            'web-local',
        )

    @api.model
    def _find_device_for_session(self, user, device_uid):
        if not user or not user.exists():
            return self.env['acpec.mobile.device']

        device_uid = (device_uid or '').strip()
        if not self._is_stable_device_uid(device_uid):
            return self.env['acpec.mobile.device']

        return self.env['acpec.mobile.device'].with_context(active_test=False).sudo().search([
            ('user_id', '=', user.id),
            ('stable_device_uid', '=', device_uid),
        ], limit=1)

    @api.model
    def _latest_session_trust_source_for_login(self, user, device_uid):
        if not user or not user.exists():
            return self.browse()

        device_uid = (device_uid or '').strip()
        if not self._is_stable_device_uid(device_uid):
            return self.browse()

        return self.sudo().search([
            ('user_id', '=', user.id),
            ('device_uid', '=', device_uid),
        ], order='write_date desc, create_date desc, id desc', limit=1)

    @api.model
    def _device_trust_values_for_device(self, device):
        if not device or not device.exists():
            return {
                'device_trust_state': 'pending_trust',
                'device_trusted_at': False,
                'device_blocked_at': False,
                'device_trust_note': False,
            }

        state = device.trust_state or 'pending_trust'
        if state not in ('trusted', 'blocked'):
            state = 'pending_trust'

        return {
            'device_trust_state': state,
            'device_trusted_at': device.trusted_at if state == 'trusted' else False,
            'device_blocked_at': device.blocked_at if state == 'blocked' else False,
            'device_trust_note': device.trust_note or device.blocked_reason or False,
        }

    @api.model
    def _device_trust_values_for_login(self, user, device_uid):
        return self._device_trust_values_for_device(
            self._find_device_for_session(user, device_uid)
        )

    @api.model
    def _assert_device_uid_can_open_session(self, user, device_uid):
        """Fail closed before opening or rotating a mobile session.

        INV-T7: every mobile session requires a stable device_uid.
        INV-D7/INV-T6: a blocked or archived user/device pair cannot open or
        refresh a session.  The refusal happens before token creation so no
        usable runtime session is emitted for a blocked durable device.
        """
        device_uid = self._normalize_stable_device_uid_or_raise(device_uid)
        device = self._find_device_for_session(user.sudo(), device_uid)
        if device:
            if not device.active:
                raise AccessError(_('Appareil mobile archivé.'))
            if device.trust_state == 'blocked':
                raise AccessError(_('Appareil mobile bloqué.'))
        else:
            legacy_source = self._latest_session_trust_source_for_login(user.sudo(), device_uid)
            if legacy_source and legacy_source.device_trust_state == 'blocked':
                raise AccessError(_('Appareil mobile bloqué.'))
        return device_uid

    @api.model
    def _get_or_create_device_for_session(self, user, device_vals=None, now=None):
        user = user.sudo().exists()
        if not user:
            raise AccessError(_('Utilisateur mobile invalide ou inactif.'))

        device_vals = device_vals or {}
        now = now or fields.Datetime.now()
        device_uid = self._assert_device_uid_can_open_session(
            user,
            device_vals.get('device_uid'),
        )

        Device = self.env['acpec.mobile.device'].with_context(active_test=False).sudo()
        device = Device.search([
            ('user_id', '=', user.id),
            ('stable_device_uid', '=', device_uid),
        ], limit=1)

        platform = device_vals.get('platform') if device_vals.get('platform') in ('android', 'ios', 'web', 'other') else False
        if not device:
            create_vals = {
                'user_id': user.id,
                'stable_device_uid': device_uid,
                'device_name': device_vals.get('device_name') or False,
                'platform': platform,
                'app_version': device_vals.get('app_version') or False,
                'first_seen_at': now,
                'last_seen_at': now,
            }
            legacy_source = self._latest_session_trust_source_for_login(user, device_uid)
            if legacy_source and legacy_source.device_trust_state == 'trusted':
                create_vals.update({
                    'trust_state': 'trusted',
                    'trusted_at': legacy_source.device_trusted_at or now,
                    'trust_note': legacy_source.device_trust_note or False,
                })
            return Device.create(create_vals)

        if not device.active:
            raise AccessError(_('Appareil mobile archivé.'))
        if device.trust_state == 'blocked':
            raise AccessError(_('Appareil mobile bloqué.'))

        # Patch43K6: le touch presence/metadata d'un device existant est
        # opportuniste. Il ne doit jamais faire echouer login/refresh.
        # La creation d'un device (branche ci-dessus) reste stricte.
        self._touch_device_metadata_best_effort(device, device_vals, now=now)
        return device

    @api.model
    def _should_touch_device_last_seen_at(self, device, now=False):
        if not device.last_seen_at:
            return True
        try:
            now_dt = fields.Datetime.to_datetime(now or fields.Datetime.now())
            last_seen_dt = fields.Datetime.to_datetime(device.last_seen_at)
            if not now_dt or not last_seen_dt:
                return True
            return (now_dt - last_seen_dt).total_seconds() >= self.DEVICE_LAST_SEEN_TOUCH_MIN_SECONDS
        except Exception:
            return True

    @api.model
    def _touch_device_metadata_best_effort(self, device, device_vals=None, now=False):
        """Patch43K6: touch presence/metadata opportuniste d'un device existant.

        Meme doctrine que Patch43J3 (session), appliquee au device :
        les ecritures critiques du refresh/login restent strictes ;
        le touch last_seen_at/metadata est throttle, isole dans un
        savepoint, et ignore proprement les conflits PostgreSQL attendus.
        """
        device_vals = device_vals or {}
        now = now or fields.Datetime.now()
        platform = device_vals.get('platform') if device_vals.get('platform') in ('android', 'ios', 'web', 'other') else False

        update_vals = {}
        if device_vals.get('device_name') and device_vals.get('device_name') != device.device_name:
            update_vals['device_name'] = device_vals.get('device_name')
        if platform and platform != device.platform:
            update_vals['platform'] = platform
        if device_vals.get('app_version') and device_vals.get('app_version') != device.app_version:
            update_vals['app_version'] = device_vals.get('app_version')
        if update_vals or self._should_touch_device_last_seen_at(device, now=now):
            update_vals['last_seen_at'] = now
        if not update_vals:
            return True

        try:
            with self.env.cr.savepoint():
                device.write(update_vals)
        except (pg_errors.SerializationFailure, pg_errors.DeadlockDetected) as exc:
            _logger.info(
                'mobile_device_last_seen_touch_skipped device_id=%s reason=%s',
                device.id,
                type(exc).__name__,
            )
        return True

    @api.model
    def _is_session_runtime_usable(self, session, now=None):
        if not session or not session.exists():
            return False
        if session.state != 'active':
            return False
        now = now or fields.Datetime.now()
        if session.expires_at and session.expires_at <= now:
            return False
        if not self._is_stable_device_uid(session.device_uid):
            return False
        device = session.device_id.with_context(active_test=False).sudo()
        if device and (not device.active or device.trust_state == 'blocked'):
            return False
        if session.device_trust_state == 'blocked':
            return False
        return True

    def _same_user_device_sessions(self):
        """Return all session rows for the same durable user/device pair."""
        self.ensure_one()
        device_uid = (self.device_uid or '').strip()
        if not self.user_id or not self._is_stable_device_uid(device_uid):
            return self

        domain = [
            ('user_id', '=', self.user_id.id),
            ('device_uid', '=', device_uid),
        ]
        if self.device_id:
            domain = [
                '|',
                ('device_id', '=', self.device_id.id),
                '&',
                ('user_id', '=', self.user_id.id),
                ('device_uid', '=', device_uid),
            ]
        return self.sudo().search(domain)

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
        device = self._get_or_create_device_for_session(user.sudo(), device_vals, now=now)
        device_uid = device.stable_device_uid
        trust_vals = self._device_trust_values_for_device(device)

        vals = {
            'user_id': user.id,
            'device_id': device.id,
            'access_token_hash': self._hash_token(access_token),
            'refresh_token_hash': self._hash_token(refresh_token),
            'expires_at': expires_at,
            'refresh_expires_at': refresh_expires_at,
            'last_seen_at': now,
            'state': 'active',
            'device_uid': device_uid,
            'device_name': device_vals.get('device_name') or device.device_name or False,
            'platform': device_vals.get('platform') if device_vals.get('platform') in ('android', 'ios', 'web', 'other') else device.platform or False,
            'app_version': device_vals.get('app_version') or device.app_version or False,
            'ip_address': device_vals.get('ip_address') or False,
            'user_agent': device_vals.get('user_agent') or False,
        }
        vals.update(trust_vals)

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

    def _should_touch_last_seen_at(self, now=False):
        self.ensure_one()
        if not self.last_seen_at:
            return True
        try:
            now_dt = fields.Datetime.to_datetime(now or fields.Datetime.now())
            last_seen_dt = fields.Datetime.to_datetime(self.last_seen_at)
            if not now_dt or not last_seen_dt:
                return True
            return (now_dt - last_seen_dt).total_seconds() >= self.ACCESS_LAST_SEEN_TOUCH_MIN_SECONDS
        except Exception:
            return True

    def _touch_last_seen_at_best_effort(self, now=False):
        now = now or fields.Datetime.now()
        for session in self.sudo().exists():
            if not session._should_touch_last_seen_at(now=now):
                continue
            try:
                with self.env.cr.savepoint():
                    session.write({'last_seen_at': now})
            except (pg_errors.SerializationFailure, pg_errors.DeadlockDetected) as exc:
                _logger.info(
                    'mobile_session_last_seen_touch_skipped session_id=%s reason=%s',
                    session.id,
                    type(exc).__name__,
                )
        return True

    @api.model
    def authenticate_access_token(self, token):
        token_hash = self._hash_token(token)
        session = self.sudo().search([('access_token_hash', '=', token_hash)], limit=1)
        if not session:
            return self.browse()
        now = fields.Datetime.now()
        if not self._is_session_runtime_usable(session, now=now):
            # L'access token est court. Son expiration ne doit pas expirer
            # la session longue tant que refresh_expires_at reste valide.
            return self.browse()
        try:
            self._check_mobile_only_user(session.user_id.sudo())
        except AccessError:
            session.sudo().write({'state': 'revoked', 'revoked_at': now})
            return self.browse()
        session._touch_last_seen_at_best_effort(now=now)
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
        successor_device_vals['device_uid'] = self._assert_device_uid_can_open_session(
            session.user_id.sudo(),
            successor_device_vals.get('device_uid'),
        )
        device = self._get_or_create_device_for_session(
            session.user_id.sudo(),
            successor_device_vals,
            now=now,
        )

        vals = {
            'user_id': session.user_id.id,
            'device_id': device.id,
            'access_token_hash': self._hash_token(access_token),
            'refresh_token_hash': self._hash_token(new_refresh_token),
            'expires_at': expires_at,
            'refresh_expires_at': refresh_expires_at,
            'last_seen_at': now,
            'state': 'active',
        }
        vals.update(successor_device_vals)
        vals['device_uid'] = device.stable_device_uid
        vals.update(self._device_trust_values_for_device(device))

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
        if not self._is_stable_device_uid(session.device_uid):
            session.sudo().write({'state': 'revoked', 'revoked_at': now})
            raise AccessError(_('Identifiant appareil mobile invalide.'))
        try:
            self._assert_device_uid_can_open_session(session.user_id.sudo(), session.device_uid)
        except AccessError as exc:
            session.sudo().write({'state': 'revoked', 'revoked_at': now})
            raise exc
        if session.device_trust_state == 'blocked':
            session.sudo().write({'state': 'revoked', 'revoked_at': now})
            raise AccessError(_('Appareil mobile bloqué.'))
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

    def _revoke_for_mobile_logout(self):
        """Revoke the current mobile session from the public logout endpoint.

        This is not a device-trust action: logout must not approve, block,
        reset, or otherwise change device trust.
        """
        now = fields.Datetime.now()
        for session in self.sudo().exists():
            if session.state == 'active':
                session.write({'state': 'revoked', 'revoked_at': now})
        return True

    def _check_single_trust_target_per_user(self):
        """Fail closed for ambiguous bulk approval on a same user.

        INV-D4 guarantees at most one trusted device per user.  Approving two
        different devices for the same user in one recordset would make the
        winning device depend on iteration order, so the batch is rejected.
        """
        targets_by_user = {}
        for session in self:
            device_uid = (session.device_uid or '').strip()
            if not session._is_stable_device_uid(device_uid):
                raise UserError('Impossible de faire confiance à une session sans identifiant device stable.')
            user_id = session.user_id.id
            if not user_id:
                continue
            previous_uid = targets_by_user.get(user_id)
            if previous_uid and previous_uid != device_uid:
                raise UserError(
                    "Impossible d'approuver plusieurs appareils différents "
                    "pour le même utilisateur en une seule action."
                )
            targets_by_user[user_id] = device_uid
        return True

    @api.model
    def _lock_device_trust_scope_for_users(self, users):
        """Serialize trust promotion per user.

        This is a surgical runtime guard, not a declarative constraint.  The
        V1 model stores trust on session rows, so approving a device first
        locks all session rows of the impacted users before resetting older
        trusted devices and promoting the selected one.
        """
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
        """Defensive invariant check for INV-D4.

        Multiple trusted session rows are allowed for the same logical device,
        but a single user must never have two distinct trusted device_uid values.
        """
        Session = self.sudo()
        for user in users.exists():
            trusted_sessions = Session.search([
                ('user_id', '=', user.id),
                ('device_trust_state', '=', 'trusted'),
                ('device_uid', '!=', False),
                ('device_uid', '!=', ''),
            ])
            trusted_device_uids = {
                (session.device_uid or '').strip()
                for session in trusted_sessions
                if Session._is_stable_device_uid(session.device_uid)
            }
            if len(trusted_device_uids) > 1:
                raise UserError(_(
                    "Un utilisateur mobile ne peut avoir qu'un seul appareil approuvé."
                ))
        return True

    def _reset_other_trusted_devices_for_user(self, user, device_uid):
        """Remove trust from other devices of the same user only.

        INV-D4: approving a new device revokes trust from previous trusted
        devices of that user.  Sessions stay technically active so the mobile
        app can still display the pending-trust state; Patch43B prevents them
        from reading or acting on business data.  Blocked devices are left
        untouched because only trusted rows are targeted.
        """
        device_uid = (device_uid or '').strip()
        if not user or not user.exists() or not self._is_stable_device_uid(device_uid):
            return self.browse()

        previous_trusted = self.sudo().search([
            ('user_id', '=', user.id),
            ('device_trust_state', '=', 'trusted'),
            ('device_uid', '!=', device_uid),
        ])
        if previous_trusted:
            previous_trusted.write({
                'device_trust_state': 'pending_trust',
                'device_trusted_at': False,
                'device_blocked_at': False,
            })
        return previous_trusted

    def _device_for_trust_action(self):
        self.ensure_one()
        if self.device_id:
            return self.device_id.with_context(active_test=False).sudo()
        return self._get_or_create_device_for_session(
            self.user_id.sudo(),
            {
                'device_uid': self.device_uid,
                'device_name': self.device_name,
                'platform': self.platform,
                'app_version': self.app_version,
            },
            now=self.last_seen_at or fields.Datetime.now(),
        )


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
                'default_session_id': self.id,
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
                'default_session_id': self.id,
                'default_operation': 'reset',
            },
        }

    def action_trust_device(self):
        self._check_device_trust_admin()
        self._check_single_trust_target_per_user()
        result = True
        for session in self:
            device = session._device_for_trust_action()
            result = device.with_context(
                acpec_mobile_source_session_id=session.id,
            ).action_trust_device()
        self.invalidate_recordset(['device_id', 'device_trust_state', 'device_trusted_at', 'device_blocked_at'])
        return result

    def action_block_device(self, reason=None):
        self._check_device_trust_admin()
        result = True
        for session in self:
            device = session._device_for_trust_action()
            result = device.with_context(
                acpec_mobile_source_session_id=session.id,
            ).action_block_device(reason=reason)
        self.invalidate_recordset(['device_id', 'device_trust_state', 'device_trusted_at', 'device_blocked_at', 'state', 'revoked_at'])
        return result

    def action_reset_device_trust(self, reason=None):
        self._check_device_trust_admin()
        result = True
        for session in self:
            device = session._device_for_trust_action()
            result = device.with_context(
                acpec_mobile_source_session_id=session.id,
            ).action_reset_device_trust(reason=reason)
        self.invalidate_recordset(['device_id', 'device_trust_state', 'device_trusted_at', 'device_blocked_at'])
        return result

    def unlink(self):
        raise UserError(_('Les sessions mobiles doivent être révoquées et non supprimées.'))
