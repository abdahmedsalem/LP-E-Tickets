# -*- coding: utf-8 -*-

import inspect
import re

from odoo.tests import tagged
from odoo.tests.common import TransactionCase

from odoo.addons.acpec_fueltoken_core.models.fuel_qr import AcpecFuelQr
from odoo.addons.acpec_fueltoken_core.models import fuel_purchase


@tagged('post_install', '-at_install')
class TestPublicQrCarnetShortCodeFormat(TransactionCase):

    def test_h8_carnet_short_code_generator_format(self):
        FaceLine = self.env['acpec.fuel.face.line'].sudo()
        code = FaceLine._generate_carnet_short_code(self.env.company)
        self.assertRegex(code, r'^[A-Z]{2}[0-9]{4}$')
        self.assertNotRegex(code, r'^C[0-9]{3,4}$')
        self.assertNotIn('-', code)

    def test_h8_purchase_uses_random_carnet_short_code_not_lot_c_sequence(self):
        source = inspect.getsource(fuel_purchase)
        self.assertIn('_generate_carnet_short_code(purchase.company_id)', source)
        self.assertIn("carnet_suffix = 'C%03d' % carnet_sequence", source)
        self.assertNotIn("carnet_short_code = '%s-%s' % (lot_short_code, carnet_suffix)", source)

    def test_h8_qr_name_uses_numeric_code_not_sequence(self):
        source = inspect.getsource(AcpecFuelQr.create)
        self.assertIn("vals['name'] = self._format_qr_numeric_code(digits)", source)
        self.assertIn("digits = self._derive_qr_numeric_code_digits", source)
        self.assertNotIn("next_by_code('acpec.fuel.qr')", source)
