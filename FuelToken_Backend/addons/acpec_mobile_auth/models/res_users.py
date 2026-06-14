from odoo import _, api, fields, models
from odoo.exceptions import ValidationError


class ResUsers(models.Model):
    _inherit = 'res.users'

    mobile_phone = fields.Char(string='Mobile Phone', index=True)
    mobile_state = fields.Selection([
        ('pending', 'Pending'),
        ('approved', 'Approved'),
        ('rejected', 'Rejected'),
    ], string='Mobile State', default='pending',)
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
        return (
            'acpec_mobile_auth.group_mobile_auth_user',
            'acpec_fueltoken_base.group_fuel_user',
            'acpec_fueltoken_base.group_fuel_station',
            'acpec_fueltoken_base.group_fuel_manager',
        )

    def _acpec_mobile_forbidden_group_xmlids(self):
        return (
            'base.group_portal',
            'base.group_user',
            'acpec_fueltoken_base.group_fuel_admin',
        )

    def _check_acpec_mobile_user_separation(self):
        mobile_group_ids = self._acpec_group_ids(self._acpec_mobile_identity_group_xmlids())
        forbidden_group_ids = self._acpec_group_ids(self._acpec_mobile_forbidden_group_xmlids())
        if not mobile_group_ids or not forbidden_group_ids:
            return

        mobile_group_users = self._acpec_users_with_group_ids(mobile_group_ids)
        mobile_phone_users = self.filtered(lambda user: bool(user.mobile_phone))
        mobile_users = mobile_group_users | mobile_phone_users
        if not mobile_users:
            return

        invalid_users = mobile_users._acpec_users_with_group_ids(forbidden_group_ids)
        if invalid_users:
            names = ', '.join(invalid_users.mapped('display_name')[:5])
            raise ValidationError(_(
                "Un utilisateur mobile FuelToken doit rester mobile-only : "
                "pas d'accès portail, pas d'accès interne Odoo et pas de groupe back-office FuelToken. "
                "Utilisateurs concernés: %s"
            ) % names)

    @api.model_create_multi
    def create(self, vals_list):
        users = super().create(vals_list)
        users._check_acpec_mobile_user_separation()
        return users

    def write(self, vals):
        result = super().write(vals)
        self._check_acpec_mobile_user_separation()
        return result
