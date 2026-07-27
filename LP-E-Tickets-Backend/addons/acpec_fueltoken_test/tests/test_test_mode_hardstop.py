import os
from unittest.mock import patch

from odoo.tests import TransactionCase, tagged

from odoo.addons.acpec_fueltoken_test.tools.test_mode import (
    is_fueltoken_test_mode_enabled,
)


@tagged('post_install', '-at_install')
class TestFuelTokenTestModeGate(TransactionCase):

    def test_fueltoken_test_mode_is_false_in_production_even_with_dev_flag(self):
        with patch.dict(os.environ, {
            'ACPEC_ENV': 'prod',
            'ODOO_ENV': '',
            'ENV': '',
            'ACPEC_FUELTOKEN_DEV_MODE': '1',
            'ACPEC_FUELTOKEN_TEST_MODE': '',
        }, clear=False):
            self.assertFalse(is_fueltoken_test_mode_enabled())

    def test_fueltoken_test_mode_can_be_enabled_by_explicit_dev_gate(self):
        with patch.dict(os.environ, {
            'ACPEC_ENV': 'dev',
            'ODOO_ENV': '',
            'ENV': '',
            'ACPEC_FUELTOKEN_DEV_MODE': '1',
            'ACPEC_FUELTOKEN_TEST_MODE': '',
        }, clear=False):
            self.assertTrue(is_fueltoken_test_mode_enabled())
