from odoo.tests.common import TransactionCase

from odoo.addons.acpec_mobile_auth.controllers.api_cors import (
    _normalize_cors_origin,
    _parse_allowed_origins,
    _preflight_headers_for_origin,
)


class TestMobileApiCors(TransactionCase):

    def _headers_dict(self, headers):
        return dict(headers)

    def test_patch43m17_wildcard_is_not_allowed(self):
        self.assertEqual(_parse_allowed_origins('*'), ())

        headers, status_code = _preflight_headers_for_origin(
            'https://evil.example',
            _parse_allowed_origins('*'),
        )

        self.assertEqual(status_code, 403)
        self.assertNotIn('Access-Control-Allow-Origin', self._headers_dict(headers))

    def test_patch43m17_allowed_origin_is_reflected(self):
        allowed_origins = _parse_allowed_origins(
            'https://mobile.acpec.example, http://localhost:3000/'
        )

        headers, status_code = _preflight_headers_for_origin(
            'https://mobile.acpec.example',
            allowed_origins,
        )
        headers = self._headers_dict(headers)

        self.assertEqual(status_code, 204)
        self.assertEqual(
            headers.get('Access-Control-Allow-Origin'),
            'https://mobile.acpec.example',
        )
        self.assertEqual(headers.get('Access-Control-Allow-Methods'), 'POST, OPTIONS')
        self.assertIn(
            'X-ACPEC-Mobile-Token',
            headers.get('Access-Control-Allow-Headers'),
        )
        self.assertEqual(headers.get('Vary'), 'Origin')

    def test_patch43m17_unlisted_origin_is_forbidden_without_cors_headers(self):
        allowed_origins = _parse_allowed_origins('https://mobile.acpec.example')

        headers, status_code = _preflight_headers_for_origin(
            'https://other.example',
            allowed_origins,
        )

        self.assertEqual(status_code, 403)
        self.assertNotIn('Access-Control-Allow-Origin', self._headers_dict(headers))

    def test_patch43m17_origin_without_browser_origin_gets_no_cors_headers(self):
        headers, status_code = _preflight_headers_for_origin(
            None,
            _parse_allowed_origins('https://mobile.acpec.example'),
        )

        self.assertEqual(status_code, 204)
        self.assertNotIn('Access-Control-Allow-Origin', self._headers_dict(headers))

    def test_patch43m17_origin_normalization_rejects_paths_and_non_http_schemes(self):
        self.assertEqual(_normalize_cors_origin('https://mobile.acpec.example/path'), '')
        self.assertEqual(_normalize_cors_origin('file://mobile.acpec.example'), '')
        self.assertEqual(
            _normalize_cors_origin('HTTPS://MOBILE.ACPEC.EXAMPLE/'),
            'https://mobile.acpec.example',
        )
