from odoo import _, api, models
from odoo.exceptions import ValidationError


class AcpecMobileAuthAccountRequest(models.Model):
    _inherit = 'acpec.mobile.auth.account.request'

    def _acpec_fueltoken_is_account_request_scope(self):
        """Return account requests subject to FuelToken phone-only signup."""
        return self.filtered(lambda rec: bool(getattr(rec.company_id, 'acpec_fueltoken_enabled', False)))

    def _check_acpec_fueltoken_signup_identifier(self):
        """Enforce phone-only signup for FuelToken without changing generic Mobile Auth."""
        user_model = self.env['res.users'].sudo()
        invalid_requests = self.env['acpec.mobile.auth.account.request']
        for record in self.sudo()._acpec_fueltoken_is_account_request_scope():
            signup_identifier = (record.signup_identifier or '').strip()
            phone = (record.phone or '').strip()
            login = (record.login or '').strip()
            if (
                record.signup_identifier_type != 'phone'
                or not phone
                or not user_model._acpec_is_canonical_mobile_phone(phone)
                or signup_identifier != phone
                or login != phone
            ):
                invalid_requests |= record

        if invalid_requests:
            names = ', '.join(
                str(rec.name or rec.signup_identifier or rec.id)
                for rec in invalid_requests[:5]
            )
            raise ValidationError(_(
                "Demande d’inscription FuelToken invalide : l’identifiant public "
                "doit être un téléphone local mauritanien canonique à 8 chiffres. "
                "signup_identifier_type doit être 'phone' et signup_identifier, "
                "phone et login doivent porter le même numéro. Demandes concernées: %s"
            ) % names)
        return True

    @api.model_create_multi
    def create(self, vals_list):
        records = super().create(vals_list)
        records._check_acpec_fueltoken_signup_identifier()
        return records

    def write(self, vals):
        result = super().write(vals)
        self._check_acpec_fueltoken_signup_identifier()
        return result

    def action_approve(self):
        self._check_acpec_fueltoken_signup_identifier()
        records = self.with_context(acpec_fueltoken_allow_mobile_phone_change=True)
        return super(AcpecMobileAuthAccountRequest, records).action_approve()
