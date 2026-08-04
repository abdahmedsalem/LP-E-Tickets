# -*- coding: utf-8 -*-
from odoo.tests.common import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestStationMapBackoffice(TransactionCase):

    def test_station_map_action_and_menu_are_available(self):
        action = self.env.ref(
            'acpec_fueltoken_backoffice_ui.action_station_map'
        )
        menu = self.env.ref(
            'acpec_fueltoken_backoffice_ui.menu_station_map'
        )

        self.assertEqual(action.url, '/fueltoken/stations/map')
        self.assertEqual(action.target, 'self')
        self.assertEqual(menu.action, action)

    def test_station_map_template_is_loaded(self):
        view = self.env.ref(
            'acpec_fueltoken_backoffice_ui.station_map_page'
        )

        self.assertIn('station-map', view.arch_db)
        self.assertIn('stations_json', view.arch_db)
