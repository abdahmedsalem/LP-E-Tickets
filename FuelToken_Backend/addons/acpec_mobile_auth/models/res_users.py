import hashlib
import hmac
import secrets

from dateutil.relativedelta import relativedelta

from odoo import _, api, fields, models
from odoo.exceptions import AccessDenied, AccessError, UserError, ValidationError


class ResUsers(models.Model):
    _inherit = 'res.users'

    mobile_phone = fields.Char(string='Mobile Phone', index=True)
    mobile_state = fields.Selection([
        ('pending', 'Pending'),
        ('approved', 'Approved'),
        ('rejected', 'Rejected'),
        ('blocked', 'Blocked'),
    ], string='Mobile State', default='pending',)
    mobile_only = fields.Boolean(
        string='Mobile Only',
        default=False,
        index=True,
        copy=False,
        help='Technical flag for FuelToken mobile-only portal users. These users authenticate through mobile OTP/session flows only.',
    )
    mobile_pin_hash = fields.Char(string='Mobile PIN Hash', copy=False, groups='base.group_system')
    mobile_pin_salt = fields.Char(string='Mobile PIN Salt', copy=False, groups='base.group_system')
    mobile_pin_set = fields.Boolean(string='Mobile PIN Set', default=False, copy=False, readonly=True)
    mobile_pin_required = fields.Boolean(string='Mobile PIN Required', default=False, copy=False)
    mobile_pin_failed_count = fields.Integer(string='Mobile PIN Failed Count', default=0, copy=False, groups='base.group_system')
    mobile_pin_locked_until = fields.Datetime(string='Mobile PIN Locked Until', copy=False, groups='base.group_system')
    mobile_pin_set_at = fields.Datetime(string='Mobile PIN Set At', readonly=True)

    def _acpec_group(self, xmlid):
        return self.env.ref(xmlid, raise_if_not_found=False)

    def _acpec_group_ids(self, xmlids):
        return [group.id for group in (self._acpec_group(xmlid) for xmlid in xmlids) if group]

    def _acpec_users_with_group_ids(self, group_ids):
        if not self or not group_ids:
            return self.env['res.users']
        self.env.cr.execute(
            """
            SELECT uid
              FROM res_groups_users_rel
             WHERE uid = ANY(%s)
               AND gid = ANY(%s)
            """,
            (list(self.ids), list(group_ids)),
        )
        user_ids = [row[0] for row in self.env.cr.fetchall()]
        return self.browse(user_ids)

    def _acpec_mobile_identity_group_xmlids(self):
        """Groups that mark a user as a FuelToken mobile identity.

        Do not include base.group_portal here: portal is the technical Odoo
        external-user type and may also be used by real web portal users.
        """
        return (
            'acpec_mobile_auth.group_mobile_auth_user',
        )

    def _acpec_mobile_baseline_group_xmlids(self):
        """Mandatory technical baseline for every FuelToken mobile-only user."""
        return (
            'base.group_portal',
            'acpec_mobile_auth.group_mobile_auth_user',
        )

    def _acpec_mobile_role_group_xmlids(self):
        """Application roles; assigned only by controlled back-office flows."""
        return (
            'acpec_fueltoken_base.group_fuel_user',
            'acpec_fueltoken_base.group_fuel_station',
            'acpec_fueltoken_base.group_fuel_manager',
        )

    def _acpec_mobile_forbidden_group_xmlids(self):
        """Groups forbidden for FuelToken mobile-only users.

        base.group_portal is intentionally allowed and required: the user is
        technically a portal-type Odoo user, but functionally mobile-only.
        """
        return (
            'base.group_user',
            'base.group_public',
            'acpec_mobile_auth.group_mobile_auth_admin',
            'acpec_fueltoken_base.group_fuel_admin',
        )

    @api.model
    def _acpec_mobile_unusable_password(self):
        """Return a long random password for mobile-only Odoo users.

        The mobile PIN must never be usable as an Odoo password.  Mobile
        authentication is OTP -> Bearer tokens; this password exists only to
        make Odoo's generic password login route unusable for 4-digit PINs.
        """
        return secrets.token_urlsafe(64)

    @api.model
    def _validate_mobile_pin(self, pin):
        pin = (str(pin) if pin not in (False, None) else '').strip()
        if not pin.isdigit() or len(pin) != 4:
            raise ValidationError(_('Le PIN mobile doit contenir exactement 4 chiffres.'))
        return pin

    @api.model
    def _new_mobile_pin_salt(self):
        return secrets.token_urlsafe(24)

    @api.model
    def _hash_mobile_pin(self, pin, salt):
        pin = self._validate_mobile_pin(pin)
        if not salt:
            raise ValidationError(_('Sel de PIN mobile manquant.'))
        return hashlib.pbkdf2_hmac(
            'sha256',
            pin.encode('utf-8'),
            salt.encode('utf-8'),
            200000,
            dklen=32,
        ).hex()

    @api.model
    def _mobile_pin_lock_seconds(self):
        return self.env["acpec.mobile.security.policy"].sudo().mobile_pin_lock_seconds()

    @api.model
    def _mobile_pin_max_attempts(self):
        return self.env["acpec.mobile.security.policy"].sudo().mobile_pin_max_attempts()

    @api.model
    def _mobile_pin_hard_block_attempts(self):
        return self.env["acpec.mobile.security.policy"].sudo().mobile_pin_hard_block_attempts()

    def _mobile_pin_lock_duration(self, failed_count):
        """Return the progressive lock duration for cumulative PIN failures.

        V1 keeps ``action_code`` as the API name of the mobile confirmation PIN,
        but the server-side lock must not be flat.  Every block of
        ``max_attempts`` failures doubles the delay, capped by policy.
        """
        max_attempts = max(1, self._mobile_pin_max_attempts())
        base_seconds = max(1, self._mobile_pin_lock_seconds())
        level = max(0, (int(failed_count or 0) - max_attempts) // max_attempts)
        return min(base_seconds * (2 ** level), 3600)

    def set_mobile_pin(self, pin):
        """Set the mobile confirmation PIN without touching res.users.password."""
        pin = self._validate_mobile_pin(pin)
        now = fields.Datetime.now()
        for user in self.sudo():
            salt = user._new_mobile_pin_salt()
            user.write({
                'mobile_pin_salt': salt,
                'mobile_pin_hash': user._hash_mobile_pin(pin, salt),
                'mobile_pin_set': True,
                'mobile_pin_required': False,
                'mobile_pin_failed_count': 0,
                'mobile_pin_locked_until': False,
                'mobile_pin_set_at': now,
            })
        return True

    def check_mobile_pin(self, pin, purpose=False):
        """Validate a mobile PIN for an authenticated mobile user.

        Patch 7.0 only provides this primitive. It must be called later from
        concrete sensitive actions after _require_mobile_auth(), never from a
        public generic /verify-pin endpoint.
        """
        pin = self._validate_mobile_pin(pin)
        now = fields.Datetime.now()
        for user in self.sudo():
            if not user.id:
                raise AccessError(_('Utilisateur mobile invalide.'))

            # Count concurrent failures correctly for the same user.
            self.env.cr.execute('SELECT id FROM res_users WHERE id = %s FOR UPDATE', (user.id,))
            user.invalidate_recordset([
                'mobile_pin_hash',
                'mobile_pin_salt',
                'mobile_pin_set',
                'mobile_pin_required',
                'mobile_pin_failed_count',
                'mobile_pin_locked_until',
            ])

            if user.mobile_pin_required or not user.mobile_pin_set or not user.mobile_pin_hash or not user.mobile_pin_salt:
                raise AccessError(_('Le PIN mobile doit être défini avant cette opération.'))
            if user.mobile_pin_locked_until and user.mobile_pin_locked_until > now:
                raise AccessError(_('Trop de tentatives PIN. Veuillez réessayer plus tard.'))

            candidate = user._hash_mobile_pin(pin, user.mobile_pin_salt)
            if hmac.compare_digest(candidate or '', user.mobile_pin_hash or ''):
                if user.mobile_pin_failed_count or user.mobile_pin_locked_until:
                    user.write({
                        'mobile_pin_failed_count': 0,
                        'mobile_pin_locked_until': False,
                    })
                continue

            failed_count = (user.mobile_pin_failed_count or 0) + 1
            vals = {'mobile_pin_failed_count': failed_count}

            hard_block_attempts = user._mobile_pin_hard_block_attempts()
            if hard_block_attempts and failed_count >= hard_block_attempts:
                vals.update({
                    'mobile_pin_hash': False,
                    'mobile_pin_salt': False,
                    'mobile_pin_set': False,
                    'mobile_pin_required': True,
                    'mobile_pin_locked_until': False,
                })
                user.write(vals)
                self.env.flush_all()
                raise AccessError(_('Trop de tentatives PIN. Réinitialisation du PIN mobile requise.'))

            if failed_count >= user._mobile_pin_max_attempts():
                vals.update({
                    'mobile_pin_locked_until': now + relativedelta(
                        seconds=user._mobile_pin_lock_duration(failed_count)
                    ),
                })
            user.write(vals)
            self.env.flush_all()
            raise AccessError(_('PIN mobile invalide.'))
        return True

    @api.model
    def _acpec_legacy_mobile_pin_users(self):
        """Return mobile-only users that still need PIN/password migration.

        Do not use a domain on groups_id here. In Odoo 19 migrations this field
        may not be available for domain optimization on res.users. Use the
        relation table directly and keep the migration narrowly scoped.
        """
        Users = self.sudo().with_context(active_test=False)

        candidates = Users.search([
            ('mobile_pin_set', '=', False),
            ('mobile_pin_required', '=', False),
            ('mobile_phone', '!=', False),
        ])

        mobile_group_ids = self._acpec_group_ids(self._acpec_mobile_identity_group_xmlids())
        if mobile_group_ids:
            self.env.cr.execute(
                """
                SELECT DISTINCT uid
                  FROM res_groups_users_rel
                 WHERE gid = ANY(%s)
                """,
                (list(mobile_group_ids),),
            )
            group_user_ids = [row[0] for row in self.env.cr.fetchall()]
            if group_user_ids:
                candidates |= Users.browse(group_user_ids).filtered(
                    lambda user: not user.mobile_pin_set and not user.mobile_pin_required
                )

        forbidden_group_ids = self._acpec_group_ids(self._acpec_mobile_forbidden_group_xmlids())
        if forbidden_group_ids and candidates:
            candidates -= candidates._acpec_users_with_group_ids(forbidden_group_ids)

        return candidates

    @api.model
    def _acpec_migrate_mobile_user_baseline(self):
        """Align existing FuelToken mobile users with the V1 baseline.

        Scope is intentionally narrow: only users already marked mobile_only or
        carrying the mobile auth identity group are migrated. We do not convert
        arbitrary portal/company users into mobile users.
        """
        Users = self.sudo().with_context(active_test=False, acpec_mobile_allow_password_write=True, no_reset_password=True)
        mobile_group_ids = self._acpec_group_ids(self._acpec_mobile_identity_group_xmlids())
        baseline_group_ids = self._acpec_group_ids(self._acpec_mobile_baseline_group_xmlids())
        forbidden_group_ids = self._acpec_group_ids(self._acpec_mobile_forbidden_group_xmlids())

        candidates = Users.search([('mobile_only', '=', True)])
        if mobile_group_ids:
            self.env.cr.execute(
                """
                SELECT DISTINCT uid
                  FROM res_groups_users_rel
                 WHERE gid = ANY(%s)
                """,
                (list(mobile_group_ids),),
            )
            group_user_ids = [row[0] for row in self.env.cr.fetchall()]
            if group_user_ids:
                candidates |= Users.browse(group_user_ids)

        migrated = 0
        for user in candidates:
            groups = set(user.group_ids.ids)
            groups.update(baseline_group_ids)
            groups.difference_update(forbidden_group_ids)
            vals = {
                'mobile_only': True,
                'group_ids': [(6, 0, sorted(groups))],
            }
            if not user.password:
                vals['password'] = user._acpec_mobile_unusable_password()
            user.write(vals)
            migrated += 1
        return migrated

    @api.model
    def _acpec_migrate_legacy_mobile_pin_credentials(self):
        """Disable legacy PIN-as-Odoo-password for existing mobile-only users.

        Existing 4-digit PINs cannot be migrated because they only exist as
        Odoo password hashes. Mark users as requiring a new mobile PIN after
        OTP, and replace their Odoo password with a long random value.
        """
        users = self._acpec_legacy_mobile_pin_users()
        for user in users:
            user.with_context(acpec_mobile_allow_password_write=True, no_reset_password=True).write({
                'password': user._acpec_mobile_unusable_password(),
                'mobile_pin_hash': False,
                'mobile_pin_salt': False,
                'mobile_pin_set': False,
                'mobile_pin_required': True,
                'mobile_pin_failed_count': 0,
                'mobile_pin_locked_until': False,
                'mobile_pin_set_at': False,
            })
        return len(users)

    def _check_acpec_mobile_user_separation(self):
        mobile_group_ids = self._acpec_group_ids(self._acpec_mobile_identity_group_xmlids())
        forbidden_group_ids = self._acpec_group_ids(self._acpec_mobile_forbidden_group_xmlids())
        baseline_group_ids = self._acpec_group_ids(self._acpec_mobile_baseline_group_xmlids())

        mobile_group_users = self._acpec_users_with_group_ids(mobile_group_ids)
        mobile_only_users = self.filtered(lambda user: bool(user.mobile_only))
        mobile_users = mobile_group_users | mobile_only_users
        if not mobile_users:
            return

        if forbidden_group_ids:
            invalid_users = mobile_users._acpec_users_with_group_ids(forbidden_group_ids)
            if invalid_users:
                names = ', '.join(
                    str(user.display_name or user.name or user.login or user.id)
                    for user in invalid_users[:5]
                )
                raise ValidationError(_(
                    "Un utilisateur mobile FuelToken doit rester mobile-only : "
                    "pas d'accès interne Odoo, pas de groupe public, pas de groupe admin mobile "
                    "et pas de groupe back-office FuelToken. Utilisateurs concernés: %s"
                ) % names)

        missing_mobile_only = mobile_group_users.filtered(lambda user: not user.mobile_only)
        if missing_mobile_only:
            names = ', '.join(
                str(user.display_name or user.name or user.login or user.id)
                for user in missing_mobile_only[:5]
            )
            raise ValidationError(_(
                "Un utilisateur avec le groupe Mobile Auth User doit être marqué mobile_only=True. "
                "Utilisateurs concernés: %s"
            ) % names)

        if baseline_group_ids:
            missing_baseline = mobile_users.filtered(
                lambda user: set(baseline_group_ids) - set(user.group_ids.ids)
            )
            if missing_baseline:
                names = ', '.join(
                    str(user.display_name or user.name or user.login or user.id)
                    for user in missing_baseline[:5]
                )
                raise ValidationError(_(
                    "Un utilisateur mobile FuelToken doit avoir la baseline technique : "
                    "base.group_portal + acpec_mobile_auth.group_mobile_auth_user. "
                    "Utilisateurs concernés: %s"
                ) % names)

    @api.model
    def _acpec_mobile_user_from_login(self, login):
        login = (login or '').strip()
        if not login:
            return self.env['res.users']
        return self.sudo().with_context(active_test=False).search([('login', '=', login)], limit=1)

    @api.model
    def _acpec_is_password_credential(self, credential):
        return isinstance(credential, dict) and credential.get('type') in (False, 'password') and bool(credential.get('password'))

    @api.model
    def _acpec_assert_not_mobile_only_password_auth(self, credential):
        if not self._acpec_is_password_credential(credential):
            return
        user = self._acpec_mobile_user_from_login(credential.get('login'))
        if user and user.mobile_only:
            raise AccessDenied()

    @api.model
    def authenticate(self, credential, user_agent_env):
        """Block Odoo password authentication for FuelToken mobile-only users.

        Mobile-only users are technically portal users, but they authenticate
        through the mobile OTP/session layer. Even if a random web password hash
        exists internally, it must not be usable on Odoo's password login flow.
        """
        self._acpec_assert_not_mobile_only_password_auth(credential)
        return super().authenticate(credential, user_agent_env)

    def _acpec_mobile_password_write_allowed(self):
        return bool(self.env.context.get('acpec_mobile_allow_password_write'))

    def _acpec_mobile_password_write_targets(self):
        if not self:
            return self.env['res.users']
        return self.sudo().with_context(active_test=False).filtered(lambda user: bool(user.mobile_only))

    def _acpec_assert_mobile_password_write_allowed(self, vals):
        if 'password' not in vals or self._acpec_mobile_password_write_allowed():
            return
        mobile_users = self._acpec_mobile_password_write_targets()
        if mobile_users:
            names = ', '.join(
                str(user.display_name or user.name or user.login or user.id)
                for user in mobile_users[:5]
            )
            raise AccessError(_(
                "Le mot de passe web d'un utilisateur mobile-only FuelToken ne peut pas être modifié "
                "par les flux Odoo standard. Utilisateurs concernés: %s"
            ) % names)

    def action_reset_password(self):
        mobile_users = self.sudo().filtered(lambda user: bool(user.mobile_only))
        if mobile_users:
            raise UserError(_("La réinitialisation du mot de passe web est désactivée pour les utilisateurs mobile-only FuelToken."))
        return super().action_reset_password()

    @api.model
    def reset_password(self, login):
        """No-op reset for mobile-only users.

        Returning True avoids leaking whether the identifier is mobile-only,
        while preventing auth_signup from issuing a web password reset token.
        """
        user = self._acpec_mobile_user_from_login(login)
        if user and user.mobile_only:
            return True
        return super().reset_password(login)

    @api.model
    def _acpec_rotate_mobile_only_web_passwords(self):
        """Rotate mobile-only Odoo passwords to unknown high-entropy values.

        This keeps the implementation Odoo-native while ensuring no migrated
        mobile-only account keeps a known or legacy web password. Password login
        is still blocked separately by authenticate().
        """
        Users = self.sudo().with_context(active_test=False, acpec_mobile_allow_password_write=True, no_reset_password=True)
        users = Users.search([('mobile_only', '=', True)])
        rotated = 0
        forbidden_group_ids = self._acpec_group_ids(self._acpec_mobile_forbidden_group_xmlids())
        for user in users:
            if forbidden_group_ids and user._acpec_users_with_group_ids(forbidden_group_ids):
                continue
            user.write({'password': user._acpec_mobile_unusable_password()})
            rotated += 1
        return rotated


    def _acpec_revoke_mobile_sessions(self):
        """Revoke active mobile sessions for mobile-only users in this recordset."""
        users = self.filtered(lambda user: bool(getattr(user, 'mobile_only', False)))
        if not users:
            return True

        sessions = self.env['acpec.mobile.session'].sudo().search([
            ('user_id', 'in', users.ids),
            ('state', '=', 'active'),
        ])
        if sessions:
            sessions.write({
                'state': 'revoked',
                'revoked_at': fields.Datetime.now(),
            })
        return True

    @api.model_create_multi
    def create(self, vals_list):
        users = super().create(vals_list)
        users._check_acpec_mobile_user_separation()
        return users

    def write(self, vals):
        self._acpec_assert_mobile_password_write_allowed(vals)
        result = super().write(vals)
        self._check_acpec_mobile_user_separation()

        should_revoke_mobile_sessions = (
            ('mobile_state' in vals and vals.get('mobile_state') != 'approved')
            or vals.get('active') is False
        )
        if should_revoke_mobile_sessions:
            self.sudo()._acpec_revoke_mobile_sessions()

        return result
