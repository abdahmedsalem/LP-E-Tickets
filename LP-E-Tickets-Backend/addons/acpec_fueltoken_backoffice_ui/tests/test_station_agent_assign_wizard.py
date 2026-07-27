# -*- coding: utf-8 -*-
from uuid import uuid4

from odoo.exceptions import ValidationError
from odoo.tests.common import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestStationAgentAssignWizard(TransactionCase):

    def _group_field_name(self):
        return 'group_ids' if 'group_ids' in self.env['res.users']._fields else 'groups_id'

    def _group_ids(self, xmlids):
        return [self.env.ref(xmlid).id for xmlid in xmlids]

    def _phone(self):
        return '21%06d' % (uuid4().int % 1000000)

    def _create_mobile_user(self, label, *, station_role=False):
        phone = self._phone()
        groups = [
            'base.group_portal',
            'acpec_mobile_auth.group_mobile_auth_user',
        ]
        if station_role:
            groups.append('acpec_fueltoken_base.group_fuel_station')

        vals = {
            'name': label,
            'login': phone,
            'mobile_phone': phone,
            'acpec_mobile_only': True,
            'acpec_mobile_state': 'approved',
            'company_id': self.env.company.id,
            'company_ids': [(6, 0, [self.env.company.id])],
            self._group_field_name(): [(6, 0, self._group_ids(groups))],
        }
        user = self.env['res.users'].sudo().create(vals)
        return user, phone

    def _create_station(self, suffix, responsible_user=False):
        vals = {
            'name': 'Station Wizard %s' % suffix,
            'code': 'WIZ-%s' % suffix,
            'company_id': self.env.company.id,
        }
        if responsible_user:
            vals['user_id'] = responsible_user.id
        return self.env['acpec.fuel.station'].sudo().create(vals)

    def _wizard(self, station, phone, *, confirm=None, responsible=False):
        return self.env['acpec.fuel.station.agent.assign.wizard'].create({
            'station_id': station.id,
            'mobile_phone': phone,
            'confirmation_mobile_phone': confirm or phone,
            'assign_as_responsible': responsible,
        })

    def test_patch43m4_station_responsible_is_optional(self):
        station = self._create_station('no-responsible-%s' % uuid4().hex[:8])
        self.assertFalse(station.user_id)

    def test_patch43m4_adds_mobile_user_as_station_agent_without_responsible(self):
        station = self._create_station('agent-only-%s' % uuid4().hex[:8])
        agent, phone = self._create_mobile_user('wizard-agent-only', station_role=False)

        wizard = self._wizard(station, phone, responsible=False)
        wizard.action_confirm()

        station.invalidate_recordset(['user_id', 'agent_ids', 'active_agent_ids'])
        agent.invalidate_recordset([self._group_field_name()])

        station_group = self.env.ref('acpec_fueltoken_base.group_fuel_station')
        self.assertIn(station_group, agent.sudo()[self._group_field_name()])
        self.assertFalse(station.user_id)

        assignment = self.env['acpec.fuel.station.agent'].sudo().search([
            ('station_id', '=', station.id),
            ('user_id', '=', agent.id),
            ('active', '=', True),
        ], limit=1)
        self.assertTrue(assignment)
        self.assertFalse(assignment.is_primary)

    def test_patch43m4_can_define_agent_as_station_responsible_when_empty(self):
        station = self._create_station('responsible-%s' % uuid4().hex[:8])
        responsible, phone = self._create_mobile_user('wizard-new-responsible', station_role=False)

        wizard = self._wizard(station, phone, responsible=True)
        wizard.action_confirm()

        station.invalidate_recordset(['user_id', 'agent_ids', 'active_agent_ids'])
        responsible.invalidate_recordset([self._group_field_name()])

        station_group = self.env.ref('acpec_fueltoken_base.group_fuel_station')
        self.assertIn(station_group, responsible.sudo()[self._group_field_name()])
        self.assertEqual(station.user_id.id, responsible.id)

        assignment = self.env['acpec.fuel.station.agent'].sudo().search([
            ('station_id', '=', station.id),
            ('user_id', '=', responsible.id),
            ('active', '=', True),
        ], limit=1)
        self.assertTrue(assignment)
        self.assertTrue(assignment.is_primary)

    def test_patch43m4_refuses_to_replace_existing_responsible(self):
        current, _current_phone = self._create_mobile_user('wizard-current-responsible', station_role=True)
        station = self._create_station('replace-refused-%s' % uuid4().hex[:8], responsible_user=current)

        candidate, phone = self._create_mobile_user('wizard-candidate-responsible', station_role=False)
        wizard = self._wizard(station, phone, responsible=True)

        with self.assertRaises(ValidationError):
            wizard.action_confirm()

        station.invalidate_recordset(['user_id'])
        self.assertEqual(station.user_id.id, current.id)
        self.assertFalse(self.env['acpec.fuel.station.agent'].sudo().search([
            ('station_id', '=', station.id),
            ('user_id', '=', candidate.id),
            ('active', '=', True),
        ]))

    def test_patch43m4_confirmation_phone_must_match(self):
        station = self._create_station('confirm-%s' % uuid4().hex[:8])
        _agent, phone = self._create_mobile_user('wizard-confirm-agent', station_role=False)

        wizard = self._wizard(station, phone, confirm='21999999', responsible=False)

        with self.assertRaises(ValidationError):
            wizard.action_confirm()

    def test_patch43m4_wizard_does_not_create_unknown_mobile_user(self):
        station = self._create_station('missing-%s' % uuid4().hex[:8])
        wizard = self._wizard(station, '21998877', responsible=False)

        before = self.env['res.users'].sudo().search_count([('login', '=', '21998877')])
        with self.assertRaises(ValidationError):
            wizard.action_confirm()
        after = self.env['res.users'].sudo().search_count([('login', '=', '21998877')])
        self.assertEqual(before, after)
