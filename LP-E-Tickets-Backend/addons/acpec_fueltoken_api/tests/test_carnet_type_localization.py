from types import SimpleNamespace

from odoo.tests import TransactionCase, tagged

from odoo.addons.acpec_fueltoken_api.controllers.api_common import AcpecFuelTokenApiCommon


@tagged('-at_install', 'post_install')
class TestCarnetTypeLocalization(TransactionCase):

    def setUp(self):
        super().setUp()
        self.controller = AcpecFuelTokenApiCommon()
        self.carnet_type = SimpleNamespace(
            name='Carnet - 10 tickets x 100 MRU',
            name_ar='دفتر - 10 تذاكر × 100 أوقية',
            code='C10T-100',
        )

    def test_arabic_name_is_selected_for_arabic(self):
        label = self.controller._carnet_type_label(
            self.carnet_type,
            language_code='ar',
        )

        self.assertEqual(label, self.carnet_type.name_ar)

    def test_arabic_name_is_selected_for_regional_arabic_locale(self):
        label = self.controller._carnet_type_label(
            self.carnet_type,
            language_code='ar-MR',
        )

        self.assertEqual(label, self.carnet_type.name_ar)

    def test_french_name_is_selected_for_french(self):
        label = self.controller._carnet_type_label(
            self.carnet_type,
            language_code='fr',
        )

        self.assertEqual(label, self.carnet_type.name)

    def test_french_name_is_fallback_when_arabic_name_is_empty(self):
        self.carnet_type.name_ar = ''

        label = self.controller._carnet_type_label(
            self.carnet_type,
            language_code='ar',
        )

        self.assertEqual(label, self.carnet_type.name)
