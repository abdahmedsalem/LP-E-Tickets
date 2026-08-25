import mimetypes
from pathlib import Path

from odoo import http
from odoo.http import request
from odoo.modules.module import get_module_path


class AcpecFuelTokenWebApp(http.Controller):

    APP_WEB_DIR = ('static', 'src', 'app')

    def _app_root(self):
        module_path = get_module_path('acpec_fueltoken_api')
        if not module_path:
            return False
        return Path(module_path).joinpath(*self.APP_WEB_DIR)

    def _serve_file(self, file_path, is_index=False):
        try:
            payload = file_path.read_bytes()
        except OSError:
            return request.not_found()

        guessed_type = mimetypes.guess_type(file_path.name)[0]
        cache_control = (
            'no-cache, max-age=0'
            if is_index
            else 'public, max-age=31536000, immutable'
        )
        headers = [
            ('Content-Type', guessed_type or 'application/octet-stream'),
            ('Content-Length', str(len(payload))),
            ('Cache-Control', cache_control),
            ('X-Content-Type-Options', 'nosniff'),
            ('X-Frame-Options', 'DENY'),
            ('Referrer-Policy', 'no-referrer'),
        ]
        if is_index:
            headers.append((
                'Content-Security-Policy',
                "default-src 'self'; "
                "script-src 'self' 'unsafe-eval' 'wasm-unsafe-eval' https://www.gstatic.com https://unpkg.com; "
                "style-src 'self' 'unsafe-inline'; "
                "img-src 'self' data: blob:; "
                "font-src 'self' data: https://fonts.gstatic.com; "
                "connect-src 'self' https://lpft.odoorim.com https://www.gstatic.com https://fonts.gstatic.com https://unpkg.com; "
                "worker-src 'self' blob:; "
                "manifest-src 'self'; "
                "base-uri 'self'; "
                "frame-ancestors 'none'",
            ))
        return request.make_response(payload, headers=headers)

    @http.route(
        ['/app', '/app/', '/app/<path:app_path>'],
        type='http',
        auth='none',
        methods=['GET'],
        csrf=False,
        sitemap=False,
    )
    def web_app(self, app_path=None, **kwargs):
        root = self._app_root()
        if not root:
            return request.not_found()

        try:
            root = root.resolve(strict=True)
        except OSError:
            return request.not_found()

        requested = (app_path or 'index.html').strip('/')
        file_path = (root / requested).resolve()
        try:
            file_path.relative_to(root)
        except ValueError:
            return request.not_found()

        is_index = file_path.name == 'index.html'
        if not file_path.is_file():
            file_path = root / 'index.html'
            is_index = True

        return self._serve_file(file_path, is_index=is_index)
