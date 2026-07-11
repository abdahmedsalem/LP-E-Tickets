# -*- coding: utf-8 -*-
from odoo import _, fields, models
from odoo.exceptions import AccessError, UserError


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

    INTERNAL_MOBILE_CONFIRM_CONTEXT = (
        'acpec_fuel_carnet_transfer_internal_mobile_confirm'
    )

    def _confirm_mobile_internal(self, actor_user=None, mobile_session=None):
        return self.sudo().with_context(
            acpec_fuel_carnet_transfer_internal_mobile_confirm=True,
        ).action_confirm_mobile(
            actor_user=actor_user,
            mobile_session=mobile_session,
        )

    def action_confirm_mobile(self, actor_user=None, mobile_session=None):
        """Confirm from mobile API and append mobile audit data."""
        self.ensure_one()
        if not (
            self.env.su
            and self.env.context.get(self.INTERNAL_MOBILE_CONFIRM_CONTEXT) is True
        ):
            raise AccessError(_(
                "La confirmation mobile d’un transfert de carnets est "
                "réservée au contrôleur API interne."
            ))
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

        self._confirm_internal(actor_user)

        self._write_internal({
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


class AcpecFuelTicketTransfer(models.Model):
    _inherit = 'acpec.fuel.ticket.transfer'

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
        """Confirm ticket transfer from mobile API and append mobile audit data."""
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

        self.sudo().with_context(allow_fuel_ticket_transfer_update=True).write({
            'mobile_session_id': mobile_session.id,
            'device_uid': mobile_session.device_uid,
        })

        txs = self.env['acpec.fuel.transaction'].sudo().search([
            ('ticket_transfer_id', '=', self.id),
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

    def init(self):
        super().init()

        # Backfill API-owned actor_user_id snapshots introduced by Patch43M5.
        # Core partner snapshots are handled by acpec_fueltoken_core.
        self.env.cr.execute(
            """
            UPDATE acpec_fuel_transaction t
               SET actor_user_id = q.consumed_user_id
              FROM acpec_fuel_qr q
             WHERE t.transaction_type = 'consommation_station'
               AND t.qr_id = q.id
               AND t.actor_user_id IS NULL
               AND q.consumed_user_id IS NOT NULL
            """
        )
        self.env.cr.execute(
            """
            UPDATE acpec_fuel_transaction t
               SET actor_user_id = tr.confirmed_by
              FROM acpec_fuel_carnet_transfer tr
             WHERE t.transfer_id = tr.id
               AND t.actor_user_id IS NULL
               AND tr.confirmed_by IS NOT NULL
            """
        )
        self.env.cr.execute(
            """
            UPDATE acpec_fuel_transaction t
               SET actor_user_id = tr.confirmed_by
              FROM acpec_fuel_ticket_transfer tr
             WHERE t.ticket_transfer_id = tr.id
               AND t.actor_user_id IS NULL
               AND tr.confirmed_by IS NOT NULL
            """
        )
