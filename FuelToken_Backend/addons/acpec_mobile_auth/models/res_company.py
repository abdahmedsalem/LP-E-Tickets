from odoo import _, fields, models
from odoo.exceptions import ValidationError


class ResCompany(models.Model):
    _inherit = 'res.company'

    acpec_mobile_auth_enabled = fields.Boolean(
        string='ACPEC Mobile Auth Enabled',
        default=False,
        help='Allow this company to appear in the mobile application and accept mobile account creation.'
    )

    def _acpec_mobile_auth_has_active_mobile_users(self):
        if not self:
            return False
        Users = self.env['res.users'].sudo().with_context(active_test=False)
        if 'acpec_mobile_only' not in Users._fields:
            return False
        return bool(Users.search([
            ('active', '=', True),
            ('acpec_mobile_only', '=', True),
            '|',
            ('company_id', 'in', self.ids),
            ('company_ids', 'in', self.ids),
        ], limit=1))

    def _check_acpec_mobile_auth_enabled_write_allowed(self, vals):
        if 'acpec_mobile_auth_enabled' not in vals or vals.get('acpec_mobile_auth_enabled'):
            return True

        companies = self.filtered(lambda company: company.acpec_mobile_auth_enabled)
        if not companies:
            return True

        if companies._acpec_mobile_auth_has_active_mobile_users():
            raise ValidationError(_(
                "ACPEC Mobile Auth ne peut pas être désactivé tant que des "
                "utilisateurs mobiles actifs sont rattachés à cette société."
            ))
        return True

    def write(self, vals):
        self._check_acpec_mobile_auth_enabled_write_allowed(vals)
        return super().write(vals)
