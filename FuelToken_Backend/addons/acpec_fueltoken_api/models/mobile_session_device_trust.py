# -*- coding: utf-8 -*-
from odoo import api, _, models
from odoo.exceptions import AccessError


class AcpecMobileSession(models.Model):
    _inherit = 'acpec.mobile.session'

    def action_trust_device(self):
        self.env['acpec.fuel.wallet'].sudo()._assert_users_have_no_non_empty_client_wallet_for_operational_mobile_role(
            self.sudo().mapped('user_id')
        )
        result = super().action_trust_device()
        self._grant_fuel_user_group_after_device_trust()
        return result

    def _grant_fuel_user_group_after_device_trust(self):
        """Accorde le groupe client Tickets Carburant après approbation appareil.

        L’OTP d’inscription rend seulement le compte mobile connectable pour
        enrôler l’appareil. L’accès métier Tickets Carburant commence quand
        un administrateur approuve l’appareil. Les rôles station et manager
        restent des décisions explicites du back-office.
        """
        fuel_group = self.env.ref(
            'acpec_fueltoken_base.group_fuel_user',
            raise_if_not_found=False,
        )
        if not fuel_group:
            return True

        forbidden_xmlids = (
            'acpec_fueltoken_base.group_fuel_station',
            'acpec_fueltoken_base.group_fuel_manager',
            'acpec_fueltoken_base.group_fuel_admin',
        )

        for session in self.sudo():
            if session.device_trust_state != 'trusted':
                continue

            user = session.user_id.sudo().exists()
            if not user:
                continue
            if not getattr(user, 'acpec_mobile_only', False):
                continue
            if getattr(user, 'acpec_mobile_state', False) not in ('self_registered', 'approved'):
                continue

            has_forbidden_group = False
            for xmlid in forbidden_xmlids:
                group = self.env.ref(xmlid, raise_if_not_found=False)
                if group and group in user.group_ids:
                    has_forbidden_group = True
                    break
            if has_forbidden_group:
                continue

            if fuel_group in user.group_ids:
                continue

            user.with_context(no_reset_password=True).write({
                'group_ids': [(4, fuel_group.id)],
            })

        return True


class AcpecMobileDevice(models.Model):
    _inherit = 'acpec.mobile.device'

    def _fueltoken_manager_approval_user(self):
        user_id = self.env.context.get('acpec_fueltoken_mobile_manager_device_approval_user_id')
        if not user_id:
            return self.env['res.users']
        user = self.env['res.users'].sudo().browse(user_id).exists()
        if not user:
            raise AccessError(_('Manager mobile introuvable pour approbation device.'))
        if not user.has_group('acpec_fueltoken_base.group_fuel_manager'):
            raise AccessError(_('Seul un manager FuelToken peut approuver un device via l’API mobile.'))
        return user

    def action_trust_device(self):
        manager_user = self._fueltoken_manager_approval_user()
        self.env['acpec.fuel.wallet'].sudo()._assert_users_have_no_non_empty_client_wallet_for_operational_mobile_role(
            self.sudo().mapped('user_id')
        )
        result = super().action_trust_device()

        if manager_user:
            devices = self.sudo()
            devices.write({'trusted_by': manager_user.id})
            for device in devices:
                device.message_post(body=(
                    'Device mobile approuvé via API manager mobile par %s.'
                    % manager_user.display_name
                ))

        sessions = self.env['acpec.mobile.session'].sudo().search([
            ('device_id', 'in', self.ids),
            ('device_trust_state', '=', 'trusted'),
        ])
        if sessions:
            sessions._grant_fuel_user_group_after_device_trust()
        return result


class ResUsers(models.Model):
    _inherit = 'res.users'

    @api.model_create_multi
    def create(self, vals_list):
        users = super().create(vals_list)
        users._fueltoken_check_operational_role_wallet_segregation()
        return users

    def write(self, vals):
        res = super().write(vals)
        watched_fields = {
            'group_ids',
            'groups_id',
            'partner_id',
            'company_ids',
            'active',
            'acpec_mobile_only',
            'acpec_mobile_state',
        }
        if watched_fields & set(vals or {}):
            self._fueltoken_check_operational_role_wallet_segregation()
        return res

    def _fueltoken_check_operational_role_wallet_segregation(self):
        self.env['acpec.fuel.wallet'].sudo()._assert_users_have_no_non_empty_client_wallet_for_operational_mobile_role(
            self.sudo()
        )
        return True
