# -*- coding: utf-8 -*-
import re

from odoo import api, fields, models, _
from odoo.exceptions import ValidationError


class AcpecFuelStationAgentAssignWizard(models.TransientModel):
    _name = 'acpec.fuel.station.agent.assign.wizard'
    _description = 'Assistant ajout agent station Tickets Carburant'

    station_id = fields.Many2one(
        'acpec.fuel.station',
        string='Station',
        required=True,
    )
    mobile_phone = fields.Char(
        string='Téléphone mobile agent',
        required=True,
    )
    confirmation_mobile_phone = fields.Char(
        string='Répéter le téléphone',
        required=True,
    )
    found_user_id = fields.Many2one(
        'res.users',
        string='Utilisateur mobile trouvé',
        readonly=True,
    )
    found_user_label = fields.Char(
        string='Utilisateur trouvé',
        readonly=True,
    )
    current_responsible_label = fields.Char(
        string='Responsable actuel',
        readonly=True,
    )
    assign_as_responsible = fields.Boolean(
        string='Définir comme responsable station',
        help=(
            "Si coché, cet utilisateur devient station.user_id. "
            "Il reste agent opérationnel et devient le responsable/superviseur "
            "de la station."
        ),
    )
    warning_message = fields.Text(
        string='Message',
        readonly=True,
    )

    @api.model
    def default_get(self, fields_list):
        vals = super().default_get(fields_list)
        if self.env.context.get('active_model') == 'acpec.fuel.station' and self.env.context.get('active_id'):
            vals.setdefault('station_id', self.env.context['active_id'])
        return vals

    @api.model
    def _normalize_mobile_phone(self, phone):
        digits = re.sub(r'\D+', '', phone or '')
        if len(digits) > 8 and digits.startswith('222'):
            digits = digits[-8:]
        return digits

    @api.model
    def _group_field_name(self):
        Users = self.env['res.users']
        if 'group_ids' in Users._fields:
            return 'group_ids'
        return 'groups_id'

    @api.model
    def _user_has_group(self, user, xmlid):
        group = self.env.ref(xmlid, raise_if_not_found=False)
        if not user or not group:
            return False
        return group in user.sudo()[self._group_field_name()]

    @api.model
    def _add_group_if_missing(self, user, xmlid):
        group = self.env.ref(xmlid, raise_if_not_found=False)
        if not group:
            raise ValidationError(_('Groupe introuvable : %s') % xmlid)
        field_name = self._group_field_name()
        if group not in user.sudo()[field_name]:
            user.sudo().write({field_name: [(4, group.id)]})

    @api.model
    def _find_mobile_user_by_phone(self, phone):
        normalized = self._normalize_mobile_phone(phone)
        if not normalized or len(normalized) != 8:
            raise ValidationError(_('Le téléphone mobile doit contenir exactement 8 chiffres.'))

        Users = self.env['res.users'].sudo().with_context(active_test=False)
        users = Users.search([
            ('mobile_only', '=', True),
            '|',
            ('mobile_phone', '=', normalized),
            ('login', '=', normalized),
        ], limit=2)
        if not users:
            return self.env['res.users']
        if len(users) > 1:
            raise ValidationError(_('Plusieurs utilisateurs mobiles correspondent à ce téléphone. Corrigez les données avant affectation.'))
        return users

    def _refresh_preview(self):
        for wizard in self:
            wizard.found_user_id = False
            wizard.found_user_label = False
            wizard.warning_message = False
            wizard.current_responsible_label = False

            if wizard.station_id and wizard.station_id.user_id:
                wizard.current_responsible_label = wizard.station_id.user_id.sudo().display_name

            if not wizard.mobile_phone:
                continue

            try:
                user = wizard._find_mobile_user_by_phone(wizard.mobile_phone)
            except ValidationError as exc:
                wizard.warning_message = str(exc)
                continue

            if not user:
                wizard.warning_message = _('Aucun utilisateur mobile trouvé pour ce téléphone.')
                continue

            wizard.found_user_id = user.id
            wizard.found_user_label = user.sudo().display_name
            if 'active' in user._fields and not user.active:
                wizard.warning_message = _('Utilisateur mobile trouvé mais archivé/inactif.')

    @api.onchange('station_id', 'mobile_phone')
    def _onchange_station_or_phone(self):
        self._refresh_preview()

    def _assert_confirmation(self, user):
        self.ensure_one()
        phone = self._normalize_mobile_phone(self.mobile_phone)
        confirmation = self._normalize_mobile_phone(self.confirmation_mobile_phone)
        if phone != confirmation:
            raise ValidationError(_('Le téléphone de confirmation ne correspond pas.'))

        user_phone = self._normalize_mobile_phone(user.mobile_phone or user.login)
        if user_phone != phone:
            raise ValidationError(_('Le téléphone confirmé ne correspond pas à l’utilisateur mobile trouvé.'))

    def _ensure_station_group(self, user):
        self.ensure_one()
        if not getattr(user, 'mobile_only', False):
            raise ValidationError(_('Ce téléphone ne correspond pas à un utilisateur mobile_only.'))
        if 'active' in user._fields and not user.active:
            raise ValidationError(_('L’utilisateur mobile est archivé/inactif.'))

        if not self._user_has_group(user, 'acpec_mobile_auth.group_mobile_auth_user'):
            raise ValidationError(_('Cet utilisateur mobile n’a pas le rôle Mobile Auth User.'))

        self._add_group_if_missing(user, 'acpec_fueltoken_base.group_fuel_station')

    def _ensure_agent_assignment(self, station, user, is_primary=False):
        Agent = self.env['acpec.fuel.station.agent'].sudo().with_context(active_test=False)
        agent = Agent.search([
            ('station_id', '=', station.id),
            ('user_id', '=', user.id),
        ], limit=1)

        if agent:
            vals = {}
            if not agent.active:
                vals.update({
                    'active': True,
                    'date_end': False,
                })
            if is_primary and not agent.is_primary:
                vals['is_primary'] = True
            if vals:
                agent.write(vals)
            return agent

        return Agent.create({
            'station_id': station.id,
            'user_id': user.id,
            'active': True,
            'is_primary': bool(is_primary),
        })

    def action_confirm(self):
        self.ensure_one()

        user = self._find_mobile_user_by_phone(self.mobile_phone)
        if not user:
            raise ValidationError(_('Aucun utilisateur mobile trouvé pour ce téléphone.'))

        self._assert_confirmation(user)

        station = self.station_id.sudo()
        if not station:
            raise ValidationError(_('Station introuvable.'))

        if station.company_id not in user.sudo().company_ids:
            raise ValidationError(_('L’agent station doit appartenir à la société de la station.'))

        if self.assign_as_responsible and station.user_id and station.user_id != user:
            raise ValidationError(_(
                'Cette station a déjà un responsable. '
                'Utilisez une action dédiée pour changer le responsable station.'
            ))

        self._ensure_station_group(user)

        if self.assign_as_responsible:
            station.write({'user_id': user.id})
            agent = self.env['acpec.fuel.station.agent'].sudo().search([
                ('station_id', '=', station.id),
                ('user_id', '=', user.id),
                ('active', '=', True),
            ], limit=1)
            if not agent:
                agent = self._ensure_agent_assignment(station, user, is_primary=True)
        else:
            agent = self._ensure_agent_assignment(station, user, is_primary=False)

        station.message_post(body=_(
            'Agent station ajouté via assistant : %(user)s%(responsible)s.'
        ) % {
            'user': user.sudo().display_name,
            'responsible': self.assign_as_responsible and _(' — défini comme responsable station') or '',
        })

        return {'type': 'ir.actions.act_window_close'}
