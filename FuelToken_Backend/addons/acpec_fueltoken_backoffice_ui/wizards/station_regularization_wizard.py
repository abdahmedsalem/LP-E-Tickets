# -*- coding: utf-8 -*-
from odoo import api, fields, models, _
from odoo.exceptions import ValidationError


class AcpecFuelStationRegularizationWizard(models.TransientModel):
    _name = 'acpec.fuel.station.regularization.wizard'
    _description = 'Régularisation des consommations station'

    reference = fields.Char(string='Référence de régularisation', required=True)
    transaction_ids = fields.Many2many(
        'acpec.fuel.transaction',
        relation='acpec_fuel_reg_wiz_tx_rel',
        column1='wizard_id',
        column2='transaction_id',
        string='Consommations station',
        readonly=True,
    )

    @api.model
    def default_get(self, fields_list):
        values = super().default_get(fields_list)
        active_ids = self.env.context.get('active_ids') or []
        if active_ids and 'transaction_ids' in fields_list:
            values['transaction_ids'] = [(6, 0, active_ids)]
        return values

    def action_regularize(self):
        self.ensure_one()
        reference = str(self.reference or '').strip()
        if not reference:
            raise ValidationError(_('La référence de régularisation est obligatoire.'))
        transactions = self.transaction_ids
        if not transactions:
            active_ids = self.env.context.get('active_ids') or []
            transactions = self.env['acpec.fuel.transaction'].browse(active_ids)
        if not transactions:
            raise ValidationError(_('Sélectionner au moins une consommation station.'))
        transactions.action_mark_station_regularized(reference)
        return {'type': 'ir.actions.act_window_close'}
