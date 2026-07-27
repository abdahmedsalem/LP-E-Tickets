# -*- coding: utf-8 -*-
from odoo.tests.common import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestCoreFuelViewsO19(TransactionCase):

    def _assert_model_views_can_load(self, model_name, view_types):
        result = self.env[model_name].get_views(
            [(False, view_type) for view_type in view_types],
            {'toolbar': True},
        )
        for view_type in view_types:
            self.assertIn(view_type, result.get('views', {}), model_name)

    def test_patch43m2_core_fuel_models_views_can_load(self):
        # Guards Odoo 19 file-backed XML arch loading for compact core views.
        for model_name, view_types in (
            ('acpec.fuel.face.line', ('list',)),
            ('acpec.fuel.qr', ('list', 'form')),
            ('acpec.fuel.station', ('list', 'form')),
            ('acpec.fuel.transaction', ('list', 'form')),
            ('acpec.fuel.wallet', ('list', 'form')),
        ):
            self._assert_model_views_can_load(model_name, view_types)

    def test_patch43m2_core_fuel_view_arch_fields_are_file_safe(self):
        # get_view_arch_from_file in Odoo 19 expects field_arch.text to be a string.
        for xmlid in (
            'acpec_fueltoken_core.view_fuel_face_line_list',
            'acpec_fueltoken_core.view_fuel_qr_list',
            'acpec_fueltoken_core.view_fuel_qr_form',
            'acpec_fueltoken_core.view_fuel_station_list',
            'acpec_fueltoken_core.view_fuel_station_form',
            'acpec_fueltoken_core.view_fuel_transaction_list',
            'acpec_fueltoken_core.view_fuel_transaction_form',
            'acpec_fueltoken_core.view_fuel_wallet_list',
            'acpec_fueltoken_core.view_fuel_wallet_form',
        ):
            view = self.env.ref(xmlid)
            self.assertTrue(view.arch_db.strip(), xmlid)
