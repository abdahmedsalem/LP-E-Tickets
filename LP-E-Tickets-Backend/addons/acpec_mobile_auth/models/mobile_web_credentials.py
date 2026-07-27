from odoo import api, models, _
from odoo.exceptions import AccessError


class AcpecMobileWebCredentialMixin(models.AbstractModel):
    _name = 'acpec.mobile.web.credential.mixin'
    _description = 'ACPEC Mobile Web Credential Guard'

    @api.model
    def _acpec_mobile_credential_block_message(self):
        return _(
            "Les credentials web Odoo sont désactivés pour les utilisateurs "
            "mobile-only FuelToken. Utilisez uniquement l'authentification mobile OTP/session."
        )

    @api.model
    def _acpec_is_mobile_only_user(self, user):
        return bool(user and user.sudo().acpec_mobile_only)

    @api.model
    def _acpec_assert_current_user_not_mobile_only_for_web_credential(self):
        if self._acpec_is_mobile_only_user(self.env.user):
            raise AccessError(self._acpec_mobile_credential_block_message())

    @api.model
    def _acpec_assert_target_user_not_mobile_only_for_web_credential(self, user):
        if self._acpec_is_mobile_only_user(user):
            raise AccessError(self._acpec_mobile_credential_block_message())

    @api.model
    def _acpec_cleanup_mobile_only_web_credentials(self):
        """Remove alternative web credentials owned by mobile-only users.

        This is intentionally best-effort/idempotent and only touches models
        that are present in the registry. It does not touch acpec.mobile.session.
        """
        Users = self.env['res.users'].sudo().with_context(active_test=False)
        mobile_users = Users.search([('acpec_mobile_only', '=', True)])
        user_ids = set(mobile_users.ids)
        cleaned = {
            'api_keys': 0,
            'totp_devices': 0,
            'totp_secrets': 0,
            'totp_wizards': 0,
            'passkeys': 0,
            'passkey_wizards': 0,
        }
        if not user_ids:
            return cleaned

        registry = self.env.registry

        if 'res.users.apikeys' in registry:
            records = self.env['res.users.apikeys'].sudo().search([('user_id', 'in', list(user_ids))])
            cleaned['api_keys'] = len(records)
            if records:
                records.unlink()

        if 'auth_totp.device' in registry:
            records = self.env['auth_totp.device'].sudo().search([('user_id', 'in', list(user_ids))])
            cleaned['totp_devices'] = len(records)
            if records:
                records.unlink()

        if 'auth_totp.wizard' in registry:
            records = self.env['auth_totp.wizard'].sudo().search([('user_id', 'in', list(user_ids))])
            cleaned['totp_wizards'] = len(records)
            if records:
                records.unlink()

        # Odoo still has legacy res.users TOTP columns in this database.
        if 'totp_secret' in Users._fields or 'totp_last_counter' in Users._fields:
            vals = {}
            if 'totp_secret' in Users._fields:
                vals['totp_secret'] = False
            if 'totp_last_counter' in Users._fields:
                vals['totp_last_counter'] = False
            if vals:
                with_secret = mobile_users.filtered(
                    lambda user: any(bool(getattr(user, field, False)) for field in vals)
                )
                cleaned['totp_secrets'] = len(with_secret)
                if with_secret:
                    with_secret.write(vals)

        # auth.passkey.key has no user_id in this DB; ownership is via create_uid.
        if 'auth.passkey.key' in registry:
            records = self.env['auth.passkey.key'].sudo().search([('create_uid', 'in', list(user_ids))])
            cleaned['passkeys'] = len(records)
            if records:
                records.unlink()

        if 'auth.passkey.key.create' in registry:
            records = self.env['auth.passkey.key.create'].sudo().search([('create_uid', 'in', list(user_ids))])
            cleaned['passkey_wizards'] = len(records)
            if records:
                records.unlink()

        return cleaned


class ResUsersApikeys(models.Model):
    _inherit = 'res.users.apikeys'

    @api.model_create_multi
    def create(self, vals_list):
        Users = self.env['res.users'].sudo().with_context(active_test=False)
        for vals in vals_list:
            user_id = vals.get('user_id') or self.env.uid
            user = Users.browse(user_id)
            self.env['acpec.mobile.web.credential.mixin']._acpec_assert_target_user_not_mobile_only_for_web_credential(user)
        return super().create(vals_list)

    def write(self, vals):
        if 'user_id' in vals:
            user = self.env['res.users'].sudo().with_context(active_test=False).browse(vals['user_id'])
            self.env['acpec.mobile.web.credential.mixin']._acpec_assert_target_user_not_mobile_only_for_web_credential(user)
        for record in self:
            self.env['acpec.mobile.web.credential.mixin']._acpec_assert_target_user_not_mobile_only_for_web_credential(record.user_id)
        return super().write(vals)


class AuthTotpDevice(models.Model):
    _inherit = 'auth_totp.device'

    @api.model_create_multi
    def create(self, vals_list):
        Users = self.env['res.users'].sudo().with_context(active_test=False)
        for vals in vals_list:
            user_id = vals.get('user_id') or self.env.uid
            user = Users.browse(user_id)
            self.env['acpec.mobile.web.credential.mixin']._acpec_assert_target_user_not_mobile_only_for_web_credential(user)
        return super().create(vals_list)

    def write(self, vals):
        if 'user_id' in vals:
            user = self.env['res.users'].sudo().with_context(active_test=False).browse(vals['user_id'])
            self.env['acpec.mobile.web.credential.mixin']._acpec_assert_target_user_not_mobile_only_for_web_credential(user)
        for record in self:
            self.env['acpec.mobile.web.credential.mixin']._acpec_assert_target_user_not_mobile_only_for_web_credential(record.user_id)
        return super().write(vals)


class AuthTotpWizard(models.TransientModel):
    _inherit = 'auth_totp.wizard'

    @api.model_create_multi
    def create(self, vals_list):
        Users = self.env['res.users'].sudo().with_context(active_test=False)
        for vals in vals_list:
            user_id = vals.get('user_id') or self.env.uid
            user = Users.browse(user_id)
            self.env['acpec.mobile.web.credential.mixin']._acpec_assert_target_user_not_mobile_only_for_web_credential(user)
        return super().create(vals_list)


class AuthPasskeyKey(models.Model):
    _inherit = 'auth.passkey.key'

    @api.model_create_multi
    def create(self, vals_list):
        self.env['acpec.mobile.web.credential.mixin']._acpec_assert_current_user_not_mobile_only_for_web_credential()
        return super().create(vals_list)

    def write(self, vals):
        self.env['acpec.mobile.web.credential.mixin']._acpec_assert_current_user_not_mobile_only_for_web_credential()
        return super().write(vals)


class AuthPasskeyKeyCreate(models.TransientModel):
    _inherit = 'auth.passkey.key.create'

    @api.model_create_multi
    def create(self, vals_list):
        self.env['acpec.mobile.web.credential.mixin']._acpec_assert_current_user_not_mobile_only_for_web_credential()
        return super().create(vals_list)
