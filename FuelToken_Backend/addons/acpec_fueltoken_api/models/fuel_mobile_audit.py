# -*- coding: utf-8 -*-
from odoo import _, fields, models
from odoo.exceptions import UserError


class AcpecFuelCarnetTransfer(models.Model):
    _inherit = 'acpec.fuel.carnet.transfer'

    mobile_session_id = fields.Many2one(
        'acpec.mobile.session',
        string='Session mobile',
        readonly=True,
        copy=False,
        index=True,
    )
    device_uid = fields.Char(
        string='Device UID mobile',
        readonly=True,
        copy=False,
        index=True,
    )

    def action_confirm_mobile(self, actor_user=None, mobile_session=None):
        """Confirm from mobile API and append mobile audit data.

        Core remains mobile-agnostic and only receives actor_user.
        Session/device audit belongs to this API module because it depends on
        both acpec_mobile_auth and acpec_fueltoken_core.
        """
        self.ensure_one()
        if not actor_user:
            raise UserError(_('Acteur mobile requis.'))
        if not mobile_session:
            raise UserError(_('Session mobile requise.'))

        mobile_session = mobile_session.sudo().exists()
        if not mobile_session:
            raise UserError(_('Session mobile invalide.'))
        if not mobile_session.device_uid:
            raise UserError(_('Device mobile non identifié.'))

        actor_user = self.env['res.users'].sudo().browse(
            actor_user.id if hasattr(actor_user, 'id') else int(actor_user or 0)
        ).exists()
        if not actor_user:
            raise UserError(_('Acteur mobile invalide.'))

        self.action_confirm(actor_user=actor_user)

        self.sudo().write({
            'mobile_session_id': mobile_session.id,
            'device_uid': mobile_session.device_uid,
        })

        txs = self.env['acpec.fuel.transaction'].sudo().search([
            ('transfer_id', '=', self.id),
        ])
        if txs:
            txs.with_context(allow_fuel_transaction_update=True).write({
                'actor_user_id': actor_user.id,
                'mobile_session_id': mobile_session.id,
                'device_uid': mobile_session.device_uid,
            })
        return True


class AcpecFuelTransaction(models.Model):
    _inherit = 'acpec.fuel.transaction'

    actor_user_id = fields.Many2one(
        'res.users',
        string='Acteur mobile',
        readonly=True,
        copy=False,
        index=True,
    )
    mobile_session_id = fields.Many2one(
        'acpec.mobile.session',
        string='Session mobile',
        readonly=True,
        copy=False,
        index=True,
    )
    device_uid = fields.Char(
        string='Device UID mobile',
        readonly=True,
        copy=False,
        index=True,
    )
