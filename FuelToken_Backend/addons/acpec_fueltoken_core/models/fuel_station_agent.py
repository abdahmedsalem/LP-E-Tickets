from odoo import api, fields, models, _
from odoo.exceptions import ValidationError


class AcpecFuelStationAgent(models.Model):
    _name = 'acpec.fuel.station.agent'
    _description = 'Affectation agent station Tickets Carburant'
    _order = 'station_id, is_primary desc, user_id'

    station_id = fields.Many2one(
        'acpec.fuel.station',
        string='Station',
        required=True,
        ondelete='cascade',
        index=True,
    )
    user_id = fields.Many2one(
        'res.users',
        string='Agent',
        required=True,
        index=True,
    )
    company_id = fields.Many2one(
        'res.company',
        string='Société',
        related='station_id.company_id',
        store=True,
        readonly=True,
        index=True,
    )
    active = fields.Boolean(default=True, index=True)
    is_primary = fields.Boolean(string='Agent principal', default=False, index=True)
    date_start = fields.Date(string='Début', default=fields.Date.context_today)
    date_end = fields.Date(string='Fin')
    note = fields.Text()

    @api.constrains('date_start', 'date_end')
    def _check_dates(self):
        for rec in self:
            if rec.date_start and rec.date_end and rec.date_end < rec.date_start:
                raise ValidationError(_('La date de fin doit être postérieure à la date de début.'))

    @api.constrains('station_id', 'user_id')
    def _check_user_company(self):
        for rec in self:
            if rec.station_id.company_id not in rec.user_id.company_ids:
                raise ValidationError(_('L’agent station doit appartenir à la société de la station.'))

    @api.constrains('user_id', 'active')
    def _check_user_station_role(self):
        for rec in self:
            if rec.active:
                rec.station_id._validate_station_mobile_user(rec.user_id)

    @api.constrains('station_id', 'user_id', 'active')
    def _check_duplicate_active_pair(self):
        for rec in self:
            if not rec.active:
                continue
            duplicate = self.search_count([
                ('id', '!=', rec.id),
                ('station_id', '=', rec.station_id.id),
                ('user_id', '=', rec.user_id.id),
                ('active', '=', True),
            ])
            if duplicate:
                raise ValidationError(_('Cet agent est déjà actif sur cette station.'))

    def is_effective_today(self):
        today = fields.Date.context_today(self)
        self.ensure_one()
        if self.date_start and self.date_start > today:
            return False
        if self.date_end and self.date_end < today:
            return False
        return True
