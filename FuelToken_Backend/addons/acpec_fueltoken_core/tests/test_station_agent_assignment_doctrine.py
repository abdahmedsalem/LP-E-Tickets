# -*- coding: utf-8 -*-
from odoo.exceptions import ValidationError
from odoo.tests.common import TransactionCase


def _acpec_test_phone(label):
    value = 2166136261
    for char in str(label):
        value ^= ord(char)
        value = (value * 16777619) % 10000000
    return '3%07d' % value


class TestStationAgentAssignmentDoctrine(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.company = cls.env.company
        cls.Users = cls.env['res.users'].sudo().with_context(no_reset_password=True)
        cls.Station = cls.env['acpec.fuel.station'].sudo()
        cls.Agent = cls.env['acpec.fuel.station.agent'].sudo()

    def _group_ids(self):
        xmlids = (
            'base.group_portal',
            'acpec_mobile_auth.group_mobile_auth_user',
            'acpec_fueltoken_base.group_fuel_station',
        )
        groups = []
        for xmlid in xmlids:
            group = self.env.ref(xmlid, raise_if_not_found=False)
            if group:
                groups.append(group.id)
        return groups

    def _station_user(self, label, state='approved', active=True):
        phone = _acpec_test_phone('h6-%s' % label)
        return self.Users.create({
            'name': 'Station Agent %s' % label,
            'login': phone,
            'mobile_phone': phone,
            'mobile_only': True,
            'mobile_state': state,
            'active': active,
            'company_id': self.company.id,
            'company_ids': [(6, 0, [self.company.id])],
            'group_ids': [(6, 0, self._group_ids())],
        })

    def _station(self, label, user=False):
        principal = user or self._station_user('principal-%s' % label, state='approved')
        return self.Station.create({
            'name': 'Station H6 %s' % label,
            'code': 'H6-%s' % label,
            'company_id': self.company.id,
            'user_id': principal.id,
        })

    def test_self_registered_station_user_can_be_assigned_as_agent(self):
        station = self._station('self-reg')
        agent_user = self._station_user('self-reg-agent', state='self_registered')

        agent = self.Agent.create({
            'station_id': station.id,
            'user_id': agent_user.id,
            'active': True,
        })

        self.assertTrue(agent)
        self.assertEqual(
            self.Station.station_for_user(agent_user).id,
            station.id,
        )

    def test_station_accepts_multiple_active_agents(self):
        station = self._station('multi')
        first = self._station_user('multi-one', state='approved')
        second = self._station_user('multi-two', state='self_registered')

        self.Agent.create({
            'station_id': station.id,
            'user_id': first.id,
            'active': True,
        })
        self.Agent.create({
            'station_id': station.id,
            'user_id': second.id,
            'active': True,
        })

        station.invalidate_recordset(['agent_ids', 'active_agent_ids'])
        active_user_ids = set(station.active_agent_ids.mapped('user_id').ids)

        self.assertIn(first.id, active_user_ids)
        self.assertIn(second.id, active_user_ids)

    def test_same_agent_cannot_be_active_on_two_stations_at_same_time(self):
        station_a = self._station('cross-a')
        station_b = self._station('cross-b')
        agent_user = self._station_user('cross-agent', state='self_registered')

        self.Agent.create({
            'station_id': station_a.id,
            'user_id': agent_user.id,
            'active': True,
        })

        with self.assertRaises(ValidationError):
            self.Agent.create({
                'station_id': station_b.id,
                'user_id': agent_user.id,
                'active': True,
            })

    def test_blocked_station_user_cannot_be_assigned_as_active_agent(self):
        station = self._station('blocked')
        blocked_user = self._station_user('blocked-agent', state='blocked')

        with self.assertRaises(ValidationError):
            self.Agent.create({
                'station_id': station.id,
                'user_id': blocked_user.id,
                'active': True,
            })

    def test_inactive_station_user_cannot_be_assigned_as_active_agent(self):
        station = self._station('inactive')
        inactive_user = self._station_user('inactive-agent', state='approved', active=False)

        with self.assertRaises(ValidationError):
            self.Agent.with_context(active_test=False).create({
                'station_id': station.id,
                'user_id': inactive_user.id,
                'active': True,
            })
