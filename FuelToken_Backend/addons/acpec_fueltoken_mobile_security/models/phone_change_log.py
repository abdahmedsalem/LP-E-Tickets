# -*- coding: utf-8 -*-
from odoo import fields, models


class AcpecFuelTokenMobilePhoneChangeLog(models.Model):
    _name = 'acpec.fueltoken.mobile.phone.change.log'
    _description = 'Historique des changements de téléphone mobile FuelToken'
    _order = 'changed_at desc, id desc'

    user_id = fields.Many2one('res.users', string='Utilisateur mobile', required=True, readonly=True, index=True, ondelete='cascade')
    partner_id = fields.Many2one('res.partner', string='Partenaire', readonly=True, index=True, ondelete='set null')
    old_phone = fields.Char(string='Ancien téléphone', readonly=True, index=True)
    new_phone = fields.Char(string='Nouveau téléphone', readonly=True, index=True)
    old_login = fields.Char(string='Ancien login', readonly=True)
    new_login = fields.Char(string='Nouveau login', readonly=True)
    old_partner_ref = fields.Char(string='Ancienne référence partenaire', readonly=True)
    new_partner_ref = fields.Char(string='Nouvelle référence partenaire', readonly=True)
    changed_by = fields.Many2one('res.users', string='Modifié par', readonly=True, default=lambda self: self.env.user, index=True)
    changed_at = fields.Datetime(string='Date du changement', readonly=True, default=fields.Datetime.now, index=True)
    reason = fields.Text(string='Motif', required=True, readonly=True)
    source = fields.Selection([
        ('backoffice', 'Back-office'),
        ('recovery', 'Récupération'),
        ('admin', 'Administration'),
    ], string='Source', default='backoffice', required=True, readonly=True)
    revoke_active_sessions = fields.Boolean(string='Sessions révoquées', readonly=True)
    active_sessions_revoked_count = fields.Integer(string='Nombre de sessions révoquées', readonly=True)
