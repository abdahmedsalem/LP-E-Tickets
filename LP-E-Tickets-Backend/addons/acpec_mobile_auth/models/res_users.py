import hashlib
import hmac
import logging
import re
import secrets

from dateutil.relativedelta import relativedelta

from odoo import _, api, fields, models, SUPERUSER_ID
from odoo.exceptions import AccessDenied, AccessError, UserError, ValidationError

from odoo.addons.acpec_mobile_auth.exceptions import MobileSensitivePinBusy

_logger = logging.getLogger(__name__)


class ResUsers(models.Model):
    _inherit = 'res.users'

    acpec_mobile_phone = fields.Char(string='Téléphone mobile FuelToken', index=True)
    acpec_mobile_state = fields.Selection([
        ('pending', 'En attente'),
        ('self_registered', 'Auto-inscrit'),
        ('approved', 'Approuvé'),
        ('rejected', 'Rejeté'),
        ('blocked', 'Bloqué'),
    ], string='État mobile', default='pending',)
    acpec_mobile_only = fields.Boolean(
        string='Utilisateur mobile uniquement',
        default=False,
        index=True,
        copy=False,
        help='Technical flag for FuelToken mobile-only portal users. These users authenticate through mobile OTP/session flows only.',
    )
    acpec_mobile_pin_hash = fields.Char(string='Mobile PIN Hash', copy=False, groups='base.group_system')
    acpec_mobile_pin_salt = fields.Char(string='Mobile PIN Salt', copy=False, groups='base.group_system')
    acpec_mobile_pin_set = fields.Boolean(string='Mobile PIN Set', default=False, copy=False, readonly=True)
    acpec_mobile_pin_required = fields.Boolean(string='Mobile PIN Required', default=False, copy=False)
    acpec_mobile_pin_failed_count = fields.Integer(string='Mobile PIN Failed Count', default=0, copy=False, groups='base.group_system')
    acpec_mobile_pin_locked_until = fields.Datetime(string='Mobile PIN Locked Until', copy=False, groups='base.group_system')
    acpec_mobile_pin_set_at = fields.Datetime(string='Mobile PIN Set At', copy=False, readonly=True, groups='base.group_system')

    acpec_human_code = fields.Char(
        string='Code humain',
        size=5,
        index=True,
        copy=False,
        readonly=True,
        help=(
            "Alias humain stable de recherche. "
            "Ne porte aucun droit, aucune authentification et aucune autorisation."
        ),
    )

    ACPEC_HUMAN_CODE_RE = re.compile(r'^[A-HJ-NP-Z][0-9]{4}$')
    ACPEC_HUMAN_CODE_LETTERS = 'ABCDEFGHJKLMNPQRSTUVWXYZ'

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
    def init(self):
        super().init()
        self.env.cr.execute("""
            SELECT EXISTS (
                SELECT 1
                  FROM information_schema.columns
                 WHERE table_name = 'res_users'
                   AND column_name = 'mobile_phone'
            )
        """)
        has_legacy_mobile_phone = self.env.cr.fetchone()[0]
        if has_legacy_mobile_phone:
            self.env.cr.execute("""
                UPDATE res_users
                   SET acpec_mobile_phone = mobile_phone
                 WHERE acpec_mobile_only IS TRUE
                   AND (acpec_mobile_phone IS NULL OR acpec_mobile_phone = '')
                   AND mobile_phone IS NOT NULL
                   AND mobile_phone <> ''
            """)

        self.env.cr.execute(
            """
            CREATE UNIQUE INDEX IF NOT EXISTS res_users_acpec_mobile_only_acpec_phone_uniq
                ON res_users (acpec_mobile_phone)
             WHERE acpec_mobile_only IS TRUE
               AND acpec_mobile_phone IS NOT NULL
               AND acpec_mobile_phone <> ''
            """
        )
        self.env.cr.execute(
            """
            CREATE UNIQUE INDEX IF NOT EXISTS res_users_acpec_human_code_uniq
                ON res_users (acpec_human_code)
             WHERE acpec_human_code IS NOT NULL
               AND acpec_human_code <> ''
            """
        )

    @api.model
    def _acpec_normalize_human_code(self, code):
        value = (str(code) if code not in (False, None) else '').strip().upper()
        return value or False

    @api.model
    def _acpec_is_valid_human_code(self, code):
        value = self._acpec_normalize_human_code(code)
        return bool(value and self.ACPEC_HUMAN_CODE_RE.match(value))

    @api.model
    def _acpec_new_human_code_candidate(self):
        return '%s%04d' % (
            secrets.choice(self.ACPEC_HUMAN_CODE_LETTERS),
            secrets.randbelow(10000),
        )

    @api.model
    def _acpec_create_unique_human_code(self, reserved_codes=False):
        reserved_codes = set(reserved_codes or [])
        Users = self.sudo().with_context(active_test=False)
        for _attempt in range(120):
            code = self._acpec_new_human_code_candidate()
            if code in reserved_codes:
                continue
            if not Users.search([('acpec_human_code', '=', code)], limit=1):
                return code
        raise ValidationError(_('Impossible de générer un code humain utilisateur unique.'))

    @api.model
    def _acpec_prepare_human_code_create_vals(self, vals_list):
        reserved_codes = set()
        for vals in vals_list:
            code = self._acpec_normalize_human_code(vals.get('acpec_human_code'))
            if code:
                if not self._acpec_is_valid_human_code(code):
                    raise ValidationError(_('Le code humain utilisateur doit respecter le format A9999.'))
                if code in reserved_codes:
                    raise ValidationError(_('Code humain utilisateur dupliqué dans la même création.'))
                vals['acpec_human_code'] = code
                reserved_codes.add(code)
                continue
            code = self._acpec_create_unique_human_code(reserved_codes=reserved_codes)
            vals['acpec_human_code'] = code
            reserved_codes.add(code)
        return vals_list

    def _acpec_assert_human_code_write_allowed(self, vals):
        if 'acpec_human_code' not in (vals or {}):
            return True

        requested = self._acpec_normalize_human_code(vals.get('acpec_human_code'))
        if requested and not self._acpec_is_valid_human_code(requested):
            raise ValidationError(_('Le code humain utilisateur doit respecter le format A9999.'))

        if self.env.context.get('acpec_allow_human_code_write'):
            vals['acpec_human_code'] = requested or False
            return True

        changed = self.filtered(lambda user: (user.acpec_human_code or False) != (requested or False))
        if changed:
            raise AccessError(_('Le code humain utilisateur est stable et ne peut pas être modifié.'))
        vals['acpec_human_code'] = requested or False
        return True

    @api.model
    def _acpec_normalize_mobile_phone(self, mobile_phone):
        """Return the stripped value only; phone identity is not repaired.

        F2B makes the mobile identity contract fail-closed: the backend accepts
        only the canonical local number already provided by the client. It does
        not convert +222/222 prefixes, spaces, dashes or any international
        presentation into an identity value.
        """
        value = (str(mobile_phone) if mobile_phone not in (False, None) else '').strip()
        return value or False

    @api.model
    def _acpec_is_valid_mobile_phone(self, mobile_phone):
        value = self._acpec_normalize_mobile_phone(mobile_phone)
        return bool(value and value.isdigit() and len(value) == 8 and value[0] in ('2', '3', '4'))

    @api.model
    def _acpec_is_canonical_mobile_phone(self, mobile_phone):
        value = (str(mobile_phone) if mobile_phone not in (False, None) else '').strip()
        return bool(value and value == self._acpec_normalize_mobile_phone(value) and self._acpec_is_valid_mobile_phone(value))

    @api.model
    def _acpec_normalize_action_name_for_match(self, name):
        """Normalize an action name for security cleanup matching.

        This intentionally stays local to back-office action cleanup. It is not
        a phone normalizer and does not alter the mobile identity contract.
        """
        import unicodedata

        value = (str(name) if name not in (False, None) else '').strip().lower()
        value = ''.join(
            char
            for char in unicodedata.normalize('NFKD', value)
            if not unicodedata.combining(char)
        )
        return ' '.join(value.split())

    @api.model
    def _acpec_is_dangerous_mobile_phone_change_action_name(self, name):
        """Return True for the V1-disabled FuelToken mobile phone change action."""
        normalized = self._acpec_normalize_action_name_for_match(name)
        exact_names = {
            self._acpec_normalize_action_name_for_match('Changer le téléphone mobile FuelToken'),
            self._acpec_normalize_action_name_for_match('Changer le telephone mobile FuelToken'),
            self._acpec_normalize_action_name_for_match('Change FuelToken mobile phone'),
            self._acpec_normalize_action_name_for_match('Change mobile phone FuelToken'),
        }
        if normalized in exact_names:
            return True

        return (
            'fueltoken' in normalized
            and ('telephone' in normalized or 'phone' in normalized)
            and ('changer' in normalized or 'change' in normalized)
        )

    @api.model
    def _acpec_action_is_bound_to_res_users(self, action):
        """Return True when an action is bound to, or directly targets, res.users."""
        binding_model = getattr(action, 'binding_model_id', False)
        if binding_model and binding_model.model == 'res.users':
            return True

        action_model = getattr(action, 'model_id', False)
        if action_model and action_model.model == 'res.users':
            return True

        res_model = getattr(action, 'res_model', False)
        if res_model == 'res.users':
            return True

        return False

    @api.model
    def _acpec_disable_dangerous_mobile_phone_change_actions(self):
        """Remove dangerous FuelToken mobile phone change actions from Odoo menus.

        V1 policy: changing the FuelToken mobile identity from the generic Odoo
        user action menu is disabled completely. A safe future flow must be a
        dedicated audited workflow that revokes sessions/devices and validates
        the old/new identity. Until then, delete matching bound actions instead
        of merely protecting them with group_ids.
        """
        removed = {}
        action_model_names = (
            'ir.actions.server',
            'ir.actions.act_window',
        )

        for model_name in action_model_names:
            if model_name not in self.env:
                continue

            Action = self.env[model_name].sudo()
            candidates = Action.browse()

            # Find exact/fuzzy FuelToken phone-change actions even if they are
            # not correctly bound, then filter in Python before unlink.
            if 'name' in Action._fields:
                candidates |= Action.search([('name', 'ilike', 'FuelToken')])
                candidates |= Action.search([('name', 'ilike', 'téléphone')])
                candidates |= Action.search([('name', 'ilike', 'telephone')])
                candidates |= Action.search([('name', 'ilike', 'phone')])

            # Also inspect every action bound to res.users, because translations
            # may make the visible label differ from the stored source name.
            if 'binding_model_id' in Action._fields:
                candidates |= Action.search([('binding_model_id.model', '=', 'res.users')])
            if 'model_id' in Action._fields:
                candidates |= Action.search([('model_id.model', '=', 'res.users')])
            if 'res_model' in Action._fields:
                candidates |= Action.search([('res_model', '=', 'res.users')])

            dangerous = candidates.filtered(
                lambda action: (
                    self._acpec_is_dangerous_mobile_phone_change_action_name(action.name)
                    and (
                        self._acpec_action_is_bound_to_res_users(action)
                        or 'fueltoken' in self._acpec_normalize_action_name_for_match(action.name)
                    )
                )
            )
            if dangerous:
                removed[model_name] = len(dangerous)
                dangerous.unlink()

        return removed

    @api.model
    def _acpec_mobile_identity_duplicate_phone_rows(self, limit=5):
        self.env.cr.execute(
            """
            SELECT acpec_mobile_phone, COUNT(*)
              FROM res_users
             WHERE acpec_mobile_only IS TRUE
               AND acpec_mobile_phone IS NOT NULL
               AND acpec_mobile_phone <> ''
             GROUP BY acpec_mobile_phone
            HAVING COUNT(*) > 1
             ORDER BY acpec_mobile_phone
             LIMIT %s
            """,
            (int(limit or 5),),
        )
        return self.env.cr.fetchall()

    @api.model
    def _acpec_prepare_mobile_phone_alias_vals(self, vals):
        """Map legacy mobile FuelToken res.users fields to acpec_* fields.

        ACPEC doctrine: custom fields on standard Odoo models must be prefixed
        with acpec_.  Public/mobile payload keys may remain unprefixed for
        compatibility, but res.users storage fields are acpec_*.

        This also prevents accidental writes to Odoo/native fields when another
        module defines a similarly named field.
        """
        vals = dict(vals or {})
        legacy_aliases = {
            'mobile_phone': 'acpec_mobile_phone',
            'mobile_state': 'acpec_mobile_state',
            'mobile_only': 'acpec_mobile_only',
            'mobile_pin_hash': 'acpec_mobile_pin_hash',
            'mobile_pin_salt': 'acpec_mobile_pin_salt',
            'mobile_pin_set': 'acpec_mobile_pin_set',
            'mobile_pin_required': 'acpec_mobile_pin_required',
            'mobile_pin_failed_count': 'acpec_mobile_pin_failed_count',
            'mobile_pin_locked_until': 'acpec_mobile_pin_locked_until',
            'mobile_pin_set_at': 'acpec_mobile_pin_set_at',
        }
        for legacy_field, acpec_field in legacy_aliases.items():
            if legacy_field in vals:
                legacy_value = vals.pop(legacy_field)
                vals.setdefault(acpec_field, legacy_value)
        return vals


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
                'acpec_mobile_pin_salt': salt,
                'acpec_mobile_pin_hash': user._hash_mobile_pin(pin, salt),
                'acpec_mobile_pin_set': True,
                'acpec_mobile_pin_required': False,
                'acpec_mobile_pin_failed_count': 0,
                'acpec_mobile_pin_locked_until': False,
                'acpec_mobile_pin_set_at': now,
            })
        return True

    def action_reset_mobile_pin(self):
        """Force mobile PIN re-initialization without knowing the new PIN.

        Back-office/admin recovery must never set a PIN on behalf of the user.
        It only clears the existing PIN and requires the mobile user to define a
        new one through an OTP reset flow.
        """
        for user in self.sudo():
            user.write({
                'acpec_mobile_pin_hash': False,
                'acpec_mobile_pin_salt': False,
                'acpec_mobile_pin_set': False,
                'acpec_mobile_pin_required': True,
                'acpec_mobile_pin_failed_count': 0,
                'acpec_mobile_pin_locked_until': False,
                'acpec_mobile_pin_set_at': False,
            })
        return True

    _MOBILE_PIN_STATE_FIELDS = [
        'acpec_mobile_pin_hash',
        'acpec_mobile_pin_salt',
        'acpec_mobile_pin_set',
        'acpec_mobile_pin_required',
        'acpec_mobile_pin_failed_count',
        'acpec_mobile_pin_locked_until',
    ]

    def _assert_mobile_pin_usable(self, user, now):
        """Reject unusable PIN state (unset/required, or currently locked).

        Neither branch mutates any counter, so this is safe to evaluate on an
        unlocked read.  The French wording is kept because
        _classify_pin_failure still maps it to the right refusal code.
        """
        if (
            user.acpec_mobile_pin_required
            or not user.acpec_mobile_pin_set
            or not user.acpec_mobile_pin_hash
            or not user.acpec_mobile_pin_salt
        ):
            raise AccessError(_('Le PIN mobile doit être défini avant cette opération.'))
        if user.acpec_mobile_pin_locked_until and user.acpec_mobile_pin_locked_until > now:
            raise AccessError(_('Trop de tentatives PIN. Veuillez réessayer plus tard.'))

    def _lock_mobile_pin_user_bounded(self, user, timeout_ms=3000):
        """Take a short, bounded row lock on res_users for counter updates.

        Patch43K1 policy: only the wrong-PIN path calls this (it raises right
        after, so no business action follows while the lock is held). The happy
        path and the valid-PIN-after-failure reset never call it. The wait is
        bounded by lock_timeout so a stuck peer can never block a mobile request
        indefinitely.  A timeout surfaces as MobileSensitivePinBusy so the
        caller reports "action already in progress" WITHOUT counting a failed
        attempt.  Contention still serializes writers (bounded wait, not
        NOWAIT), so the failure counter stays accurate.
        """
        cr = self.env.cr
        cr.execute("SELECT current_setting('lock_timeout')")
        previous_timeout = cr.fetchone()[0]
        try:
            with cr.savepoint():
                # SET LOCAL is savepoint-scoped: a rollback below reverts it.
                cr.execute("SET LOCAL lock_timeout = %s", ('%dms' % int(timeout_ms),))
                cr.execute('SELECT id FROM res_users WHERE id = %s FOR UPDATE', (user.id,))
        except Exception as exc:
            # 55P03 = lock_not_available (lock_timeout elapsed). The savepoint
            # rollback already cleared the aborted state and reverted SET LOCAL.
            if getattr(exc, 'pgcode', None) == '55P03':
                raise MobileSensitivePinBusy(_(
                    'Une autre opération sensible est déjà en cours pour ce compte. '
                    'Veuillez réessayer dans quelques secondes.'
                ))
            raise
        finally:
            # Restore the prior lock_timeout for the rest of the request tx
            # (matters on the valid-PIN-after-failure path, which continues
            # into the business action after the reset).
            cr.execute("SET LOCAL lock_timeout = %s", (previous_timeout,))

    def _reset_mobile_pin_counters_committed(self, user):
        """Clear PIN failure counters in a short, independent transaction.

        A valid PIN entered after earlier failures must reset the counters, but
        the sensitive business action that follows must NOT run while holding a
        res_users row lock.  ANY write to res_users on the request cursor holds
        that row lock until the request commits — i.e. across the whole business
        action.  We therefore commit the reset on its own cursor, which releases
        the lock immediately, before the business transaction proceeds.

        Best-effort and bounded: on contention we skip it (the counter
        self-heals on the next valid PIN) rather than blocking or failing an
        otherwise-valid action.  A lost update here is benign — a valid PIN
        legitimately resets, and if a concurrent failure wins the counter simply
        stays higher.
        """
        try:
            with self.env.registry.cursor() as cr:
                cr.execute("SET LOCAL lock_timeout = '3000ms'")
                env = api.Environment(cr, SUPERUSER_ID, {})
                locked_user = env['res.users'].browse(user.id)
                if locked_user.acpec_mobile_pin_failed_count or locked_user.acpec_mobile_pin_locked_until:
                    locked_user.write({
                        'acpec_mobile_pin_failed_count': 0,
                        'acpec_mobile_pin_locked_until': False,
                    })
                # cursor __exit__ commits and releases the row lock
        except Exception:
            _logger.warning(
                'Réinitialisation du compteur PIN ignorée (contention/erreur), '
                'auto-guérison au prochain PIN valide',
                exc_info=True,
            )

    def check_mobile_pin(self, pin, purpose=False):
        """Validate a mobile PIN for an authenticated mobile user.

        Patch 7.0 only provides this primitive. It must be called later from
        concrete sensitive actions after _require_mobile_auth(), never from a
        public generic /verify-pin endpoint.

        Locking policy (Patch43K1):
        - The request transaction NEVER holds a res_users row lock into the
          business action. In PostgreSQL a FOR UPDATE (or any write) taken on
          the request cursor is held until that transaction commits, i.e. across
          the whole business action; RELEASE SAVEPOINT does not free it. So no
          res_users lock/write is left pending on the request cursor here.
        - Valid PIN, nothing to reset: no lock at all.
        - Valid PIN after earlier failures: counters are reset in a SEPARATE
          committed transaction (see _reset_mobile_pin_counters_committed) that
          releases its lock immediately, before the business action runs.
        - Wrong PIN: the increment is serialized under a short bounded lock and
          then RAISES; no business action follows a raise, so holding that lock
          until the (fast) error commit blocks nothing.
        - Lock contention raises MobileSensitivePinBusy and is never counted as
          a failed attempt.
        """
        pin = self._validate_mobile_pin(pin)
        now = fields.Datetime.now()
        pin_fields = self._MOBILE_PIN_STATE_FIELDS
        for user in self.sudo():
            if not user.id:
                raise AccessError(_('Utilisateur mobile invalide.'))

            # Unlocked read: enough to authorize the common valid-PIN case.
            user.invalidate_recordset(pin_fields)
            user._assert_mobile_pin_usable(user, now)

            candidate = user._hash_mobile_pin(pin, user.acpec_mobile_pin_salt)
            pin_is_valid = hmac.compare_digest(candidate or '', user.acpec_mobile_pin_hash or '')

            if pin_is_valid:
                if user.acpec_mobile_pin_failed_count or user.acpec_mobile_pin_locked_until:
                    # Valid PIN after earlier failures: reset the counters in a
                    # SEPARATE committed transaction so the business action that
                    # follows never runs while holding a res_users row lock.
                    user._reset_mobile_pin_counters_committed(user)
                continue

            # Wrong PIN: serialize the counter update under a short bounded lock,
            # then raise. No business action runs after a raise, so holding the
            # lock until the request commits does not block anything. Re-read
            # authoritative state under the lock so a concurrent lockout or
            # hard-block is honoured and the increment starts from a fresh count.
            user._lock_mobile_pin_user_bounded(user)
            user.invalidate_recordset(pin_fields)
            user._assert_mobile_pin_usable(user, now)

            failed_count = (user.acpec_mobile_pin_failed_count or 0) + 1
            vals = {'acpec_mobile_pin_failed_count': failed_count}

            hard_block_attempts = user._mobile_pin_hard_block_attempts()
            if hard_block_attempts and failed_count >= hard_block_attempts:
                vals.update({
                    'acpec_mobile_pin_hash': False,
                    'acpec_mobile_pin_salt': False,
                    'acpec_mobile_pin_set': False,
                    'acpec_mobile_pin_required': True,
                    'acpec_mobile_pin_locked_until': False,
                })
                user.write(vals)
                self.env.flush_all()
                raise AccessError(_('Trop de tentatives PIN. Réinitialisation du PIN mobile requise.'))

            if failed_count >= user._mobile_pin_max_attempts():
                vals.update({
                    'acpec_mobile_pin_locked_until': now + relativedelta(
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
            ('acpec_mobile_pin_set', '=', False),
            ('acpec_mobile_pin_required', '=', False),
            ('acpec_mobile_phone', '!=', False),
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
                    lambda user: not user.acpec_mobile_pin_set and not user.acpec_mobile_pin_required
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

        candidates = Users.search([('acpec_mobile_only', '=', True)])
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
                'acpec_mobile_only': True,
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
                'acpec_mobile_pin_hash': False,
                'acpec_mobile_pin_salt': False,
                'acpec_mobile_pin_set': False,
                'acpec_mobile_pin_required': True,
                'acpec_mobile_pin_failed_count': 0,
                'acpec_mobile_pin_locked_until': False,
                'acpec_mobile_pin_set_at': False,
            })
        return len(users)

    def _check_acpec_mobile_user_separation(self):
        mobile_group_ids = self._acpec_group_ids(self._acpec_mobile_identity_group_xmlids())
        forbidden_group_ids = self._acpec_group_ids(self._acpec_mobile_forbidden_group_xmlids())
        baseline_group_ids = self._acpec_group_ids(self._acpec_mobile_baseline_group_xmlids())

        mobile_group_users = self._acpec_users_with_group_ids(mobile_group_ids)
        mobile_only_users = self.filtered(lambda user: bool(user.acpec_mobile_only))
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

        missing_mobile_only = mobile_group_users.filtered(lambda user: not user.acpec_mobile_only)
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
        if user and user.acpec_mobile_only:
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
        return self.sudo().with_context(active_test=False).filtered(lambda user: bool(user.acpec_mobile_only))

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
        mobile_users = self.sudo().filtered(lambda user: bool(user.acpec_mobile_only))
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
        if user and user.acpec_mobile_only:
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
        users = Users.search([('acpec_mobile_only', '=', True)])
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
        users = self.filtered(lambda user: bool(getattr(user, 'acpec_mobile_only', False)))
        if not users:
            return True

        sessions = self.env['acpec.mobile.session'].sudo().search([
            ('user_id', 'in', users.ids),
            ('state', '=', 'active'),
        ])
        if sessions:
            sessions._write_internal({
                'state': 'revoked',
                'revoked_at': fields.Datetime.now(),
            })
        return True

    @api.model_create_multi
    def create(self, vals_list):
        vals_list = [
            self._acpec_prepare_mobile_phone_alias_vals(vals)
            for vals in vals_list
        ]
        vals_list = [dict(vals) for vals in vals_list]
        self._acpec_prepare_human_code_create_vals(vals_list)
        users = super().create(vals_list)
        users._check_acpec_mobile_user_separation()
        return users

    def write(self, vals):
        vals = self._acpec_prepare_mobile_phone_alias_vals(vals)
        vals = dict(vals or {})
        self._acpec_assert_human_code_write_allowed(vals)
        self._acpec_assert_mobile_password_write_allowed(vals)
        result = super().write(vals)
        self._check_acpec_mobile_user_separation()

        should_revoke_mobile_sessions = (
            ('acpec_mobile_state' in vals and vals.get('acpec_mobile_state') not in ('approved', 'self_registered'))
            or vals.get('active') is False
        )
        if should_revoke_mobile_sessions:
            self.sudo()._acpec_revoke_mobile_sessions()

        return result
