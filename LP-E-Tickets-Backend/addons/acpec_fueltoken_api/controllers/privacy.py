from pathlib import Path

from odoo import http
from odoo.http import request
from odoo.modules.module import get_module_path


class LpETicketsPrivacyController(http.Controller):

    def _static_privacy_response(self, filename, robots_tag=False):
        module_path = get_module_path('acpec_fueltoken_api')
        if not module_path:
            return request.not_found()

        page_path = Path(module_path) / 'static' / 'src' / 'privacy' / filename
        try:
            page = page_path.read_text(encoding='utf-8')
        except (OSError, UnicodeError):
            return request.not_found()

        headers = [
            ('Content-Type', 'text/html; charset=utf-8'),
            ('Cache-Control', 'public, max-age=3600'),
            ('X-Content-Type-Options', 'nosniff'),
            ('X-Frame-Options', 'DENY'),
            ('Referrer-Policy', 'no-referrer'),
            (
                'Content-Security-Policy',
                "default-src 'self'; style-src 'self'; img-src 'self' data:; "
                "base-uri 'none'; frame-ancestors 'none'; form-action 'none'",
            ),
        ]
        if robots_tag:
            headers.append(('X-Robots-Tag', robots_tag))

        return request.make_response(page, headers=headers)

    @http.route(
        '/privacy',
        type='http',
        auth='none',
        methods=['GET'],
        csrf=False,
        sitemap=False,
    )
    def privacy_policy(self, **kwargs):
        return self._static_privacy_response(
            'google_play_privacy.html',
            robots_tag='noindex, nofollow, noarchive',
        )

    @http.route(
        ['/account-deletion', '/delete-account', '/data-deletion'],
        type='http',
        auth='none',
        methods=['GET'],
        csrf=False,
        sitemap=True,
    )
    def account_deletion(self, **kwargs):
        return self._static_privacy_response('account_deletion.html')
