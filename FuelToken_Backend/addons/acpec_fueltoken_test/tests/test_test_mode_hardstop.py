import os
from unittest.mock import patch

from odoo.tests import TransactionCase, tagged

from odoo.addons.acpec_fueltoken_test.tools.test_mode import (
    is_fueltoken_test_mode_enabled,
)


@tagged('post_install', '-at_install')
class TestFuelTokenTestModeHardStop(TransactionCase):

    def test_fueltoken_test_mode_rejects_production_runtime(self):
        with patch.dict(os.environ, {
            'ACPEC_ENV': 'prod',
            'ACPEC_FUELTOKEN_TEST_MODE': '1',
        }, clear=False):
            with self.assertRaises(RuntimeError):
                is_fueltoken_test_mode_enabled()

    def test_fueltoken_test_mode_can_be_enabled_outside_production(self):
        with patch.dict(os.environ, {
            'ACPEC_ENV': 'dev',
            'ACPEC_FUELTOKEN_TEST_MODE': '1',
        }, clear=False):
            self.assertTrue(is_fueltoken_test_mode_enabled())
