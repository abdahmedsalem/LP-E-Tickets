from odoo import api, fields, models, _
from odoo.exceptions import ValidationError


class AcpecFuelStation(models.Model):
    _name = 'acpec.fuel.station'
    _description = 'Station FuelToken'
    _inherit = ['mail.thread', 'mail.activity.mixin']
    _order = 'name'

    name = fields.Char(string='Station', required=True, tracking=True)
    code = fields.Char(string='Code', index=True)
    user_id = fields.Many2one('res.users', string='Utilisateur station', required=True, index=True, tracking=True)
    company_id = fields.Many2one('res.company', string='Société', required=True, default=lambda self: self.env.company, index=True)
    active = fields.Boolean(default=True)

    _sql_constraints = [
        ('user_unique', 'unique(user_id)', 'Un utilisateur station ne peut être lié qu’à une seule station.'),
        ('code_company_unique', 'unique(code, company_id)', 'Le code station doit être unique par société.'),
    ]

    @api.constrains('user_id', 'company_id')
    def _check_station_user_company(self):
        for rec in self:
            if rec.company_id not in rec.user_id.company_ids:
                raise ValidationError(_('L’utilisateur station doit appartenir à la société de la station.'))

    @api.model
    def station_for_user(self, user):
        station = self.sudo().search([('user_id', '=', user.id), ('active', '=', True)], limit=1)
        if not station:
            raise ValidationError(_('Aucune station active n’est liée à cet utilisateur.'))
        if station.company_id not in user.company_ids:
            raise ValidationError(_('La station n’appartient pas aux sociétés autorisées de cet utilisateur.'))
        return station
