import inspect
from pathlib import Path

from odoo.tests.common import TransactionCase

from odoo.addons.acpec_fueltoken_api.controllers.api_mobile import (
    AcpecFuelTokenMobileApi,
)


class TestQrManualCodeSecrecyH11(TransactionCase):

    def _addons_root(self):
        return Path(__file__).resolve().parents[2]

    def test_qr_name_uses_sequence_and_not_manual_code_source_contract(self):
        source = (
            self._addons_root()
            / 'acpec_fueltoken_core'
            / 'models'
            / 'fuel_qr.py'
        ).read_text(encoding='utf-8')

        self.assertIn("next_by_code('acpec.fuel.qr')", source)
        self.assertIn('_check_name_is_not_qr_manual_code', source)
        self.assertNotIn(
            "vals['name'] = self._format_qr_numeric_code(digits)",
            source,
        )

    def test_mobile_standard_qr_payload_excludes_manual_code(self):
        source = inspect.getsource(AcpecFuelTokenMobileApi._qr_payload)

        self.assertIn("'name': qr.name", source)
        self.assertIn("'public_code': qr.public_code", source)
        self.assertNotIn("'qr_numeric_code'", source)
        self.assertNotIn('_qr_numeric_code_display()', source)

    def test_mobile_reveal_code_is_sensitive_and_dedicated(self):
        source = (
            self._addons_root()
            / 'acpec_fueltoken_api'
            / 'controllers'
            / 'api_mobile.py'
        ).read_text(encoding='utf-8')

        self.assertIn('/api/acpec/fueltoken/v1/mobile/qr/reveal-code', source)
        self.assertIn('def qr_reveal_code', source)
        self.assertIn("purpose='qr_reveal_code'", source)
        self.assertIn("'qr_numeric_code': qr._qr_numeric_code_display()", source)

    def test_station_manual_input_contract_is_preserved(self):
        source = (
            self._addons_root()
            / 'acpec_fueltoken_api'
            / 'controllers'
            / 'api_station.py'
        ).read_text(encoding='utf-8')

        self.assertIn("qr_numeric_code=(params or {}).get('qr_numeric_code')", source)
        self.assertIn("request_hash_params.pop('qr_numeric_code', None)", source)
