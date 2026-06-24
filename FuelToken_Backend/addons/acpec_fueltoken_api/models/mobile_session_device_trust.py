# -*- coding: utf-8 -*-
from odoo import models


class AcpecMobileSession(models.Model):
    _inherit = 'acpec.mobile.session'

    def action_trust_device(self):
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
            if not getattr(user, 'mobile_only', False):
                continue
            if getattr(user, 'mobile_state', False) not in ('self_registered', 'approved'):
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
