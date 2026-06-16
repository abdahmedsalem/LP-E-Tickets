from odoo import http
from odoo.http import request


class AcpecMobileAuthCorsApi(http.Controller):
    """CORS preflight support for Flutter Web mobile API calls.

    Browser clients send an OPTIONS preflight before JSON-RPC POST calls.
    Odoo jsonrpc routes reject body-less OPTIONS requests with 415, so the
    preflight must be answered by a small HTTP route before the real POST.
    """

    @http.route(
        '/api/acpec/mobile_auth/v1/<path:subpath>',
        type='http',
        auth='none',
        methods=['OPTIONS'],
        csrf=False,
        cors='*',
    )
    def mobile_auth_preflight(self, subpath=None, **kwargs):
        headers = [
            ('Access-Control-Allow-Origin', '*'),
            ('Access-Control-Allow-Methods', 'POST, OPTIONS'),
            ('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-ACPEC-Mobile-Token, X-Requested-With'),
            ('Access-Control-Max-Age', '86400'),
        ]
        response = request.make_response('', headers=headers)
        response.status_code = 204
        return response
