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

    def test_qr_manual_secret_uses_dedicated_security_settings_model(self):
        qr_source = (
            self._addons_root()
            / 'acpec_fueltoken_core'
            / 'models'
            / 'fuel_qr.py'
        ).read_text(encoding='utf-8')
        settings_source = (
            self._addons_root()
            / 'acpec_fueltoken_core'
            / 'models'
            / 'fuel_security_settings.py'
        ).read_text(encoding='utf-8')
        init_source = (
            self._addons_root()
            / 'acpec_fueltoken_core'
            / 'models'
            / '__init__.py'
        ).read_text(encoding='utf-8')
        access_source = (
            self._addons_root()
            / 'acpec_fueltoken_core'
            / 'security'
            / 'ir.model.access.csv'
        ).read_text(encoding='utf-8')

        self.assertIn(
            "QR_NUMERIC_SECRET_MODEL = 'acpec.fueltoken.security.settings'",
            qr_source,
        )
        self.assertIn('def _qr_numeric_code_settings', qr_source)
        self.assertIn('def _qr_numeric_code_secret', qr_source)
        self.assertNotIn("config.get('database.secret')", qr_source)
        self.assertNotIn("config.get('admin_passwd')", qr_source)
        self.assertNotIn('or self.env.cr.dbname', qr_source)
        self.assertNotIn("or 'acpec-fueltoken'", qr_source)
        self.assertNotIn('acpec.fueltoken.qr_numeric_secret', qr_source)

        self.assertIn("_name = 'acpec.fueltoken.security.settings'", settings_source)
        self.assertIn("company_id = fields.Many2one", settings_source)
        self.assertIn("qr_numeric_secret = fields.Char", settings_source)
        self.assertIn('QR_NUMERIC_SECRET_MIN_LENGTH = 32', settings_source)
        self.assertIn('def _ensure_qr_numeric_secret', settings_source)
        self.assertIn('def _qr_numeric_secret_status', settings_source)
        self.assertIn('def write', settings_source)
        self.assertIn('def unlink', settings_source)
        self.assertIn('allow_qr_numeric_secret_recovery', settings_source)
        self.assertIn('from . import fuel_security_settings', init_source)
        self.assertIn('model_acpec_fueltoken_security_settings', access_source)

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
