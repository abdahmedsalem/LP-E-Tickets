from odoo import api, fields, models, _
from odoo.exceptions import ValidationError


class AcpecFuelStation(models.Model):
    _name = 'acpec.fuel.station'
    _description = 'Station Tickets Carburant'
    _inherit = ['mail.thread', 'mail.activity.mixin']
    _order = 'name'

    name = fields.Char(string='Station', required=True, tracking=True)
    code = fields.Char(string='Code', index=True)
    user_id = fields.Many2one(
        'res.users',
        string='Utilisateur station principal',
        required=True,
        index=True,
        tracking=True,
    )
    agent_ids = fields.One2many(
        'acpec.fuel.station.agent',
        'station_id',
        string='Agents autorisés',
    )
    active_agent_ids = fields.One2many(
        'acpec.fuel.station.agent',
        'station_id',
        string='Agents actifs',
        domain=[('active', '=', True)],
    )
    company_id = fields.Many2one('res.company', string='Société', required=True, default=lambda self: self.env.company, index=True)
    active = fields.Boolean(default=True)

    _user_unique = models.Constraint(
        'UNIQUE(user_id)',
        'Un utilisateur station ne peut être lié qu’à une seule station.',
    )
    _code_company_unique = models.Constraint(
        'UNIQUE(code, company_id)',
        'Le code station doit être unique par société.',
    )

    @api.model
    def _user_has_group_xmlid(self, user, xmlid):
        group = self.env.ref(xmlid, raise_if_not_found=False)
        if not user or not group:
            return False

        user = user.sudo()
        if 'group_ids' in user._fields:
            return group in user.group_ids
        if 'groups_id' in user._fields:
            return group in user.groups_id

        self.env.cr.execute(
            '''
            select 1
              from res_groups_users_rel
             where gid = %s
               and uid = %s
             limit 1
            ''',
            (group.id, user.id),
        )
        return bool(self.env.cr.fetchone())

    @api.model
    def _validate_station_mobile_user(self, user):
        if not user:
            raise ValidationError(_('Utilisateur station introuvable.'))

        required_groups = (
            'acpec_mobile_auth.group_mobile_auth_user',
            'acpec_fueltoken_base.group_fuel_station',
        )
        missing = [
            xmlid for xmlid in required_groups
            if not self._user_has_group_xmlid(user, xmlid)
        ]
        if missing:
            raise ValidationError(_(
                'Un agent station doit être un utilisateur mobile-only avec le rôle station.'
            ))

        forbidden_groups = (
            'base.group_user',
            'base.group_portal',
            'base.group_public',
            'acpec_fueltoken_base.group_fuel_admin',
        )
        forbidden = [
            xmlid for xmlid in forbidden_groups
            if self._user_has_group_xmlid(user, xmlid)
        ]
        if forbidden:
            raise ValidationError(_(
                'Un utilisateur mobile station ne doit être ni utilisateur interne Odoo, '
                'ni portail, ni public, ni admin back-office FuelToken.'
            ))

        if 'mobile_state' in user._fields and user.mobile_state != 'approved':
            raise ValidationError(_('L’utilisateur mobile station doit être approuvé.'))

    @api.constrains('user_id', 'company_id')
    def _check_station_user_company(self):
        for rec in self:
            if rec.company_id not in rec.user_id.company_ids:
                raise ValidationError(_('L’utilisateur station doit appartenir à la société de la station.'))
            rec._validate_station_mobile_user(rec.user_id)

    @api.model_create_multi
    def create(self, vals_list):
        records = super().create(vals_list)
        records._sync_primary_agents()
        return records

    def write(self, vals):
        res = super().write(vals)
        if {'user_id', 'company_id', 'active'} & set(vals):
            self._sync_primary_agents()
        return res

    def _sync_primary_agents(self):
        Agent = self.env['acpec.fuel.station.agent'].sudo()
        for station in self.sudo():
            if not station.user_id:
                continue

            old_primary_agents = Agent.search([
                ('station_id', '=', station.id),
                ('is_primary', '=', True),
                ('user_id', '!=', station.user_id.id),
                ('active', '=', True),
            ])
            if old_primary_agents:
                old_primary_agents.write({'active': False})

            agent = Agent.search([
                ('station_id', '=', station.id),
                ('user_id', '=', station.user_id.id),
            ], limit=1)

            vals = {
                'station_id': station.id,
                'user_id': station.user_id.id,
                'active': bool(station.active),
                'is_primary': True,
            }
            if agent:
                agent.write(vals)
            else:
                Agent.create(vals)

    @api.model
    def _effective_agent_domain(self, user):
        today = fields.Date.context_today(self)
        return [
            ('user_id', '=', user.id),
            ('active', '=', True),
            ('station_id.active', '=', True),
            '|', ('date_start', '=', False), ('date_start', '<=', today),
            '|', ('date_end', '=', False), ('date_end', '>=', today),
        ]

    @api.model
    def station_for_user(self, user):
        agent = self.env['acpec.fuel.station.agent'].sudo().search(
            self._effective_agent_domain(user),
            order='is_primary desc, id',
            limit=1,
        )
        if agent:
            station = agent.station_id
            if station.company_id not in user.company_ids:
                raise ValidationError(_('La station n’appartient pas aux sociétés autorisées de cet utilisateur.'))
            return station

        # Compatibilité legacy : les stations créées avant le modèle agent
        # restent fonctionnelles. Au premier usage, on crée l’agent principal.
        station = self.sudo().search([('user_id', '=', user.id), ('active', '=', True)], limit=1)
        if not station:
            raise ValidationError(_('Aucune station active n’est liée à cet utilisateur.'))
        if station.company_id not in user.company_ids:
            raise ValidationError(_('La station n’appartient pas aux sociétés autorisées de cet utilisateur.'))
        station._sync_primary_agents()
        return station
