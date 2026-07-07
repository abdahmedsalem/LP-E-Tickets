from urllib.parse import urlparse

from odoo import http
from odoo.http import request


CORS_ALLOWED_ORIGINS_PARAM = 'acpec_mobile_auth.cors_allowed_origins'
CORS_ALLOWED_METHODS = 'POST, OPTIONS'
CORS_ALLOWED_HEADERS = (
    'Content-Type, Authorization, X-ACPEC-Mobile-Token, X-Requested-With'
)
CORS_MAX_AGE_SECONDS = '86400'


def _normalize_cors_origin(origin):
    if not origin:
        return ''

    value = origin.strip()
    parsed = urlparse(value)
    if parsed.scheme.lower() not in ('http', 'https'):
        return ''
    if not parsed.netloc:
        return ''
    if parsed.params or parsed.query or parsed.fragment:
        return ''
    if parsed.path not in ('', '/'):
        return ''

    return '%s://%s' % (parsed.scheme.lower(), parsed.netloc.lower())


def _parse_allowed_origins(raw_value):
    origins = []
    seen = set()
    for item in (raw_value or '').split(','):
        normalized = _normalize_cors_origin(item)
        if not normalized:
            continue
        if normalized in seen:
            continue
        seen.add(normalized)
        origins.append(normalized)
    return tuple(origins)


def _preflight_headers_for_origin(origin, allowed_origins):
    normalized_origin = _normalize_cors_origin(origin)
    headers = [('Vary', 'Origin')]

    if not normalized_origin:
        return headers, 204

    if normalized_origin not in set(allowed_origins or ()):
        return headers, 403

    headers.extend([
        ('Access-Control-Allow-Origin', normalized_origin),
        ('Access-Control-Allow-Methods', CORS_ALLOWED_METHODS),
        ('Access-Control-Allow-Headers', CORS_ALLOWED_HEADERS),
        ('Access-Control-Max-Age', CORS_MAX_AGE_SECONDS),
    ])
    return headers, 204


class AcpecMobileAuthCorsApi(http.Controller):
    """CORS preflight support for browser-based mobile API calls.

    Native Android/iOS clients do not require CORS. Browser clients, including
    Flutter Web, must use an explicit origin allowlist configured by the
    ``acpec_mobile_auth.cors_allowed_origins`` system parameter.

    The real JSON-RPC POST routes keep their normal authentication, token,
    device trust and action-code checks. This controller only answers OPTIONS.
    """

    @http.route(
        '/api/acpec/mobile_auth/v1/<path:subpath>',
        type='http',
        auth='none',
        methods=['OPTIONS'],
        csrf=False,
    )
    def mobile_auth_preflight(self, subpath=None, **kwargs):
        allowed_origins_raw = request.env['ir.config_parameter'].sudo().get_param(
            CORS_ALLOWED_ORIGINS_PARAM,
            '',
        )
        allowed_origins = _parse_allowed_origins(allowed_origins_raw)
        origin = request.httprequest.headers.get('Origin')

        headers, status_code = _preflight_headers_for_origin(origin, allowed_origins)
        response = request.make_response('', headers=headers)
        response.status_code = status_code
        return response
