from odoo import _, api, models
from odoo.exceptions import ValidationError


class ResUsers(models.Model):
    _inherit = 'res.users'

    def _acpec_fueltoken_is_mobile_identity_scope(self):
        """Return FuelToken mobile users subject to the phone-only identity rule.

        acpec_mobile_auth stays generic and may support phone or email identifiers.
        FuelToken is stricter: when a mobile-only user belongs to the unique
        FuelToken company, the mobile identity is the local phone number.
        """
        return self.filtered(
            lambda user: bool(user.mobile_only)
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
            phone = (user.mobile_phone or '').strip()
            if not phone or not user._acpec_is_canonical_mobile_phone(phone) or login != phone:
                invalid_users |= user

        if invalid_users:
            names = ', '.join(
                str(user.display_name or user.name or user.login or user.id)
                for user in invalid_users[:5]
            )
            raise ValidationError(_(
                "Identité mobile FuelToken invalide : pour un utilisateur mobile-only "
                "rattaché à la société Tickets Carburant, login et mobile_phone "
                "doivent être le même numéro local mauritanien canonique à 8 chiffres. "
                "Utilisateurs concernés: %s"
            ) % names)
        return True

    @api.model_create_multi
    def create(self, vals_list):
        users = super().create(vals_list)
        users._check_acpec_fueltoken_mobile_identity()
        return users

    def write(self, vals):
        result = super().write(vals)
        self._check_acpec_fueltoken_mobile_identity()
        return result
