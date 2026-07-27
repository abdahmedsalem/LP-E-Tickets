import re
from odoo import _, api, models
from odoo.exceptions import ValidationError


class ResUsers(models.Model):
    _inherit = 'res.users'

    _ACPEC_FUELTOKEN_MOBILE_PARTNER_IDENTITY_CONTEXT = 'acpec_fueltoken_allow_mobile_partner_identity_sync'
    _ACPEC_FUELTOKEN_MOBILE_NAME_PREFIX_RE = re.compile(r'^\s*\d{8}\s*-\s*')

    def _acpec_fueltoken_is_mobile_identity_scope(self):
        """Return FuelToken mobile users subject to the phone-only identity rule.

        acpec_mobile_auth stays generic and may support phone or email identifiers.
        FuelToken is stricter: when a mobile-only user belongs to the unique
        FuelToken company, the mobile identity is the local phone number.
        """
        return self.filtered(
            lambda user: bool(user.acpec_mobile_only)
            and bool(
                getattr(user.company_id, 'acpec_fueltoken_enabled', False)
                or any(getattr(company, 'acpec_fueltoken_enabled', False) for company in user.company_ids)
            )
        )

    def _check_acpec_fueltoken_mobile_identity(self):
        """Enforce INV-I1 and INV-I5 for FuelToken mobile identities."""
        invalid_users = self.env['res.users']
        for user in self.sudo()._acpec_fueltoken_is_mobile_identity_scope():
            login = (user.login or '').strip()
            phone = (user.acpec_mobile_phone or '').strip()
            if not phone or not user._acpec_is_canonical_mobile_phone(phone) or login != phone:
                invalid_users |= user

        if invalid_users:
            names = ', '.join(
                str(user.display_name or user.name or user.login or user.id)
                for user in invalid_users[:5]
            )
            raise ValidationError(_(
                "Identité mobile FuelToken invalide : pour un utilisateur mobile-only "
                "rattaché à la société Tickets Carburant, login et acpec_mobile_phone "
                "doivent être le même numéro local mauritanien canonique à 8 chiffres. "
                "Utilisateurs concernés: %s"
            ) % names)
        return True

    @api.model
    def _acpec_fueltoken_strip_mobile_name_prefix(self, name):
        label = (name or '').strip()
        while label:
            new_label = self._ACPEC_FUELTOKEN_MOBILE_NAME_PREFIX_RE.sub('', label).strip()
            if new_label == label:
                break
            label = new_label
        return label

    @api.model
    def _acpec_fueltoken_mobile_canonical_name(self, phone, name):
        phone = (phone or '').strip()
        label = self._acpec_fueltoken_strip_mobile_name_prefix(name or '').strip()
        if not label or label == phone:
            label = _('Utilisateur mobile')
        if not phone:
            return label
        return '%s - %s' % (phone, label)

    @api.model
    def _acpec_fueltoken_prepare_mobile_identity_create_vals(self, vals_list):
        prepared = []
        for vals in vals_list:
            vals = dict(vals or {})
            phone = (vals.get('acpec_mobile_phone') or vals.get('mobile_phone') or vals.get('login') or '').strip()
            if (vals.get('acpec_mobile_only') or vals.get('acpec_mobile_phone') or vals.get('mobile_phone')) and self._acpec_is_canonical_mobile_phone(phone):
                vals['name'] = self._acpec_fueltoken_mobile_canonical_name(phone, vals.get('name') or '')
            prepared.append(vals)
        return prepared

    def _acpec_fueltoken_mobile_partner_identity_vals(self):
        self.ensure_one()
        phone = (self.acpec_mobile_phone or '').strip()
        if not self._acpec_is_canonical_mobile_phone(phone):
            return {}
        return {
            'name': self._acpec_fueltoken_mobile_canonical_name(phone, self.name or ''),
            'ref': 'MOB:%s' % phone,
            'acpec_is_mobile_partner': True,
        }

    def _sync_acpec_fueltoken_mobile_partner_identity(self):
        for user in self.sudo()._acpec_fueltoken_is_mobile_identity_scope():
            partner = user.partner_id.sudo()
            if not partner:
                continue
            vals = user._acpec_fueltoken_mobile_partner_identity_vals()
            changes = {}
            for field, value in vals.items():
                if field not in partner._fields:
                    continue
                current = partner[field]
                if hasattr(current, 'id'):
                    current = current.id or False
                if (current or False) != (value or False):
                    changes[field] = value
            if changes:
                partner.with_context(**{
                    self._ACPEC_FUELTOKEN_MOBILE_PARTNER_IDENTITY_CONTEXT: True,
                }).write(changes)
        return True

    def _check_acpec_fueltoken_mobile_user_technical_identity_write_allowed(self, vals):
        if self.env.context.get(self._ACPEC_FUELTOKEN_MOBILE_PARTNER_IDENTITY_CONTEXT):
            return True

        locked_fields = {'name', 'acpec_mobile_only'} & set(vals or {})

        if not locked_fields:
            return True

        blocked_users = self.env['res.users']
        for user in self.sudo()._acpec_fueltoken_is_mobile_identity_scope():
            if not user._acpec_fueltoken_has_established_mobile_identity():
                continue
            for field in locked_fields:
                if field not in user._fields:
                    continue
                current = user[field]
                if hasattr(current, 'id'):
                    current = current.id or False
                new_value = vals.get(field)
                if isinstance(new_value, (list, tuple)):
                    blocked_users |= user
                    break
                if (current or False) != (new_value or False):
                    blocked_users |= user
                    break

        if blocked_users:
            labels = ', '.join(
                user._acpec_fueltoken_user_label_for_error()
                for user in blocked_users[:5]
            )
            if len(blocked_users) > 5:
                labels = '%s, ... (+%s)' % (labels, len(blocked_users) - 5)
            raise ValidationError(_(
                "Identité technique utilisateur mobile FuelToken verrouillée : les champs %s "
                "ne peuvent pas être modifiés directement. Utilisez les actions contrôlées. "
                "Utilisateurs concernés: %s"
            ) % (', '.join(sorted(locked_fields)), labels))
        return True

    def _acpec_fueltoken_user_label_for_error(self):
        self.ensure_one()
        name = (self.name or self.display_name or '').strip()
        login = (self.login or '').strip()
        if name and login:
            return '%s (login: %s)' % (name, login)
        if name:
            return '%s (login: -)' % name
        if login:
            return 'Utilisateur #%s (login: %s)' % (self.id, login)
        return 'Utilisateur #%s (login: -)' % self.id

    def _acpec_fueltoken_has_established_mobile_identity(self):
        self.ensure_one()
        login = (self.login or '').strip()
        phone = (self.acpec_mobile_phone or '').strip()
        return bool(
            login
            and phone
            and login == phone
            and self._acpec_is_canonical_mobile_phone(phone)
        )

    def _check_acpec_fueltoken_mobile_phone_write_allowed(self, vals):
        vals = dict(vals or {})
        touched_fields = {'login', 'acpec_mobile_phone'} & set(vals)
        if not touched_fields:
            return True

        allow_initialization = bool(
            self.env.context.get('acpec_fueltoken_allow_mobile_identity_initialization')
        )

        checked_users = self.sudo()
        candidate_users = checked_users._acpec_fueltoken_is_mobile_identity_scope()
        if vals.get('acpec_mobile_only') is True:
            candidate_users |= checked_users

        blocked_users = self.env['res.users']
        for user in candidate_users:
            login_changed = (
                'login' in vals
                and (vals.get('login') or '').strip() != (user.login or '').strip()
            )
            phone_changed = (
                'acpec_mobile_phone' in vals
                and (vals.get('acpec_mobile_phone') or '').strip() != (user.acpec_mobile_phone or '').strip()
            )
            if not (login_changed or phone_changed):
                continue

            if allow_initialization and not user._acpec_fueltoken_has_established_mobile_identity():
                continue

            blocked_users |= user

        if blocked_users:
            labels = ', '.join(
                user._acpec_fueltoken_user_label_for_error()
                for user in blocked_users[:5]
            )
            if len(blocked_users) > 5:
                labels = '%s, ... (+%s)' % (labels, len(blocked_users) - 5)
            raise ValidationError(_(
                "Identité mobile FuelToken verrouillée : login et acpec_mobile_phone "
                "ne peuvent pas être modifiés directement. Bloquez l’ancienne identité "
                "et créez une nouvelle identité mobile. Utilisateurs concernés: %s"
            ) % labels)
        return True

    def _acpec_fueltoken_duplicate_phone_user(self, new_phone):
        return self.env['res.users'].with_context(active_test=False).sudo().search([
            ('id', 'not in', self.ids),
            ('acpec_mobile_only', '=', True),
            '|',
            ('login', '=', new_phone),
            ('acpec_mobile_phone', '=', new_phone),
        ], limit=1)

    def action_fueltoken_change_mobile_phone(self, new_phone, reason, source='backoffice'):
        raise ValidationError(_(
            "Identité mobile FuelToken verrouillée : une identité établie ne peut pas changer de téléphone. "
            "Bloquez l’ancienne identité et créez une nouvelle identité mobile."
        ))

    @api.model_create_multi
    def create(self, vals_list):
        vals_list = [
            self._acpec_prepare_mobile_phone_alias_vals(vals)
            for vals in vals_list
        ]
        vals_list = self._acpec_fueltoken_prepare_mobile_identity_create_vals(vals_list)
        created_users = super(
            ResUsers,
            self.with_context(**{
                self._ACPEC_FUELTOKEN_MOBILE_PARTNER_IDENTITY_CONTEXT: True,
                'acpec_fueltoken_allow_mobile_identity_initialization': True,
            }),
        ).create(vals_list)
        users = self.browse(created_users.ids)
        users._check_acpec_fueltoken_mobile_identity()
        users._sync_acpec_fueltoken_mobile_partner_identity()
        return users

    def write(self, vals):
        vals = self._acpec_prepare_mobile_phone_alias_vals(vals)
        self._check_acpec_fueltoken_mobile_user_technical_identity_write_allowed(vals)
        self._check_acpec_fueltoken_mobile_phone_write_allowed(vals)
        result = super().write(vals)
        self._check_acpec_fueltoken_mobile_identity()
        if {'name', 'login', 'acpec_mobile_phone', 'acpec_mobile_only'} & set(vals or {}):
            self._sync_acpec_fueltoken_mobile_partner_identity()
        return result
