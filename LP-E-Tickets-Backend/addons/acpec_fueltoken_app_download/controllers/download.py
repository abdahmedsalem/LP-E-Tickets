import mimetypes
from pathlib import Path

from odoo import http
from odoo.http import request
from odoo.modules.module import get_module_path


class LpETicketsDownloadController(http.Controller):

    APK_CANDIDATES = (
        'LP-E-Tickets.apk',
    )
    APP_WEB_DIR = ('static', 'src', 'app')

    def _serve_static_file(self, file_path, download_name, content_type=None):
        try:
            payload = file_path.read_bytes()
        except OSError:
            return request.not_found()

        guessed_type = content_type or mimetypes.guess_type(file_path.name)[0]
        return request.make_response(
            payload,
            headers=[
                ('Content-Type', guessed_type or 'application/octet-stream'),
                ('Content-Length', str(len(payload))),
                ('Content-Disposition', f'attachment; filename="{download_name}"'),
                ('Cache-Control', 'no-store, max-age=0'),
                ('X-Content-Type-Options', 'nosniff'),
                ('X-Frame-Options', 'DENY'),
                ('Referrer-Policy', 'no-referrer'),
                ('X-Robots-Tag', 'noindex, nofollow, noarchive'),
            ],
        )

    @http.route(
        '/download',
        type='http',
        auth='none',
        methods=['GET'],
        csrf=False,
        sitemap=False,
    )
    def download_page(self, **kwargs):
        module_path = get_module_path('acpec_fueltoken_app_download')
        if not module_path:
            return request.not_found()

        page_path = (
            Path(module_path)
            / 'static'
            / 'src'
            / 'download'
            / 'app_download.html'
        )
        try:
            page = page_path.read_text(encoding='utf-8')
        except (OSError, UnicodeError):
            return request.not_found()

        return request.make_response(
            page,
            headers=[
                ('Content-Type', 'text/html; charset=utf-8'),
                ('Cache-Control', 'public, max-age=3600'),
                ('X-Content-Type-Options', 'nosniff'),
                ('X-Frame-Options', 'DENY'),
                ('Referrer-Policy', 'no-referrer'),
                ('X-Robots-Tag', 'noindex, nofollow, noarchive'),
                (
                    'Content-Security-Policy',
                    "default-src 'self'; style-src 'self'; img-src 'self' data:; "
                    "base-uri 'none'; frame-ancestors 'none'; form-action 'none'",
                ),
            ],
        )

    def _app_web_root(self):
        module_path = get_module_path('acpec_fueltoken_app_download')
        if not module_path:
            return False
        return Path(module_path).joinpath(*self.APP_WEB_DIR)

    def _serve_app_file(self, file_path, root, is_index=False):
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
                "script-src 'self' 'unsafe-eval' 'wasm-unsafe-eval' https://unpkg.com; "
                "style-src 'self' 'unsafe-inline'; "
                "img-src 'self' data: blob:; "
                "font-src 'self' data:; "
                "connect-src 'self' https://lpft.odoorim.com https://unpkg.com; "
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
        root = self._app_web_root()
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

        is_index = False
        if not file_path.is_file():
            file_path = root / 'index.html'
            is_index = True
        else:
            is_index = file_path.name == 'index.html'

        return self._serve_app_file(file_path, root, is_index=is_index)

    @http.route(
        '/download/app.apk',
        type='http',
        auth='none',
        methods=['GET'],
        csrf=False,
        sitemap=False,
    )
    def download_mobile_app(self, **kwargs):
        module_path = get_module_path('acpec_fueltoken_app_download')
        if not module_path:
            return request.not_found()

        download_dir = (
            Path(module_path)
            / 'static'
            / 'src'
            / 'download'
        )
        apk_path = None
        for candidate in self.APK_CANDIDATES:
            candidate_path = download_dir / candidate
            if candidate_path.is_file():
                apk_path = candidate_path
                break

        if apk_path is None:
            return request.redirect('/download')

        download_name = 'LP E-Tickets.apk'
        return self._serve_static_file(
            apk_path,
            download_name,
            'application/vnd.android.package-archive',
        )
