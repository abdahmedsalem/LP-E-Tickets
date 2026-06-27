# -*- coding: utf-8 -*-
from markupsafe import Markup, escape

from odoo import _, fields, models
from odoo.exceptions import AccessError, UserError


class ResUsers(models.Model):
    _inherit = 'res.users'

    def _check_acpec_fueltoken_mobile_user_state_admin(self):
        if not self.env.user.has_group('acpec_mobile_auth.group_mobile_auth_admin'):
            raise AccessError(_("Seul un administrateur sécurité mobile peut bloquer ou réactiver un utilisateur mobile."))
        return True

    def _acpec_fueltoken_required_reason(self, reason):
        reason = (reason or '').strip()
        if not reason:
            raise UserError(_("Le motif est obligatoire."))
        return reason

    def _acpec_fueltoken_post_mobile_user_state_note(self, previous_state, new_state, reason, source):
        self.ensure_one()
        partner = self.partner_id.sudo()
        body = Markup(
            "<p><b>{title}</b></p>"
            "<ul>"
            "<li><b>Utilisateur :</b> {user}</li>"
            "<li><b>Téléphone :</b> {phone}</li>"
            "<li><b>Ancien état :</b> {previous}</li>"
            "<li><b>Nouvel état :</b> {new}</li>"
            "<li><b>Source :</b> {source}</li>"
            "<li><b>Acteur BO :</b> {actor}</li>"
            "<li><b>Motif :</b> {reason}</li>"
            "</ul>"
        ).format(
            title=escape(_("Sécurité mobile — changement état utilisateur")),
            user=escape(self.display_name or self.login or self.id),
            phone=escape(self.mobile_phone or self.login or ''),
            previous=escape(previous_state or ''),
            new=escape(new_state or ''),
            source=escape(source or 'backoffice'),
            actor=escape(self.env.user.display_name or self.env.user.login or self.env.uid),
            reason=escape(reason),
        )
        partner.message_post(
            body=body,
            message_type='comment',
            subtype_xmlid='mail.mt_note',
        )

    def action_fueltoken_block_mobile_user(self, reason, source='backoffice'):
        self._check_acpec_fueltoken_mobile_user_state_admin()
        reason = self._acpec_fueltoken_required_reason(reason)

        for user in self:
            if not user.mobile_only:
                raise UserError(_("Seuls les utilisateurs mobiles peuvent être bloqués par cette action."))
            if user.mobile_state == 'blocked':
                raise UserError(_("L'utilisateur mobile est déjà bloqué."))

            previous_state = user.mobile_state or False
            user.sudo().write({'mobile_state': 'blocked'})
            user.invalidate_recordset(['mobile_state', 'active'])
            user._acpec_fueltoken_post_mobile_user_state_note(
                previous_state,
                'blocked',
                reason,
                source,
            )
        return True

    def action_fueltoken_reactivate_mobile_user(self, reason, target_state='self_registered', source='backoffice'):
        self._check_acpec_fueltoken_mobile_user_state_admin()
        reason = self._acpec_fueltoken_required_reason(reason)

        if target_state not in ('self_registered', 'approved'):
            raise UserError(_("L'état cible de réactivation doit être self_registered ou approved."))

        for user in self:
            if not user.mobile_only:
                raise UserError(_("Seuls les utilisateurs mobiles peuvent être réactivés par cette action."))
            if user.mobile_state != 'blocked':
                raise UserError(_("Seul un utilisateur mobile bloqué peut être réactivé."))

            previous_state = user.mobile_state or False
            user.sudo().write({'mobile_state': target_state})
            user.invalidate_recordset(['mobile_state', 'active'])
            user._acpec_fueltoken_post_mobile_user_state_note(
                previous_state,
                target_state,
                reason,
                source,
            )
        return True

    def action_open_fueltoken_block_mobile_user_wizard(self):
        self.ensure_one()
        self._check_acpec_fueltoken_mobile_user_state_admin()
        return {
            'type': 'ir.actions.act_window',
            'name': _("Bloquer utilisateur mobile"),
            'res_model': 'acpec.fueltoken.mobile.user.state.wizard',
            'view_mode': 'form',
            'target': 'new',
            'context': {
                'default_user_id': self.id,
                'default_operation': 'block',
            },
        }

    def action_open_fueltoken_reactivate_mobile_user_wizard(self):
        self.ensure_one()
        self._check_acpec_fueltoken_mobile_user_state_admin()
        return {
            'type': 'ir.actions.act_window',
            'name': _("Réactiver utilisateur mobile"),
            'res_model': 'acpec.fueltoken.mobile.user.state.wizard',
            'view_mode': 'form',
            'target': 'new',
            'context': {
                'default_user_id': self.id,
                'default_operation': 'reactivate',
                'default_target_state': 'self_registered',
            },
        }
