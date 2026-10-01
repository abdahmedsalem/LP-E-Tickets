#!/usr/bin/env python3
import http.server
import os
import urllib.request
import urllib.error
import urllib.parse
from pathlib import Path

PORT = int(os.environ.get('PORT', 8091))
ODOO_ORIGIN = os.environ.get('ODOO_ORIGIN', 'http://127.0.0.1:8069')
WEB_ROOT = Path(__file__).resolve().parent.parent / 'build' / 'web'


class ReusableHTTPServer(http.server.HTTPServer):
    allow_reuse_address = True


class ProxyHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(WEB_ROOT), **kwargs)

    def do_GET(self):
        if self.path.startswith('/api/acpec/'):
            self._proxy()
            return
        # Vérifie si le fichier existe, sinon fallback vers index.html (SPA routing Flutter)
        req_path = self.path.split('?')[0].lstrip('/')
        file_path = WEB_ROOT / req_path
        if not file_path.is_file():
            self.path = '/index.html'
        super().do_GET()

    def do_POST(self):
        if self.path.startswith('/api/acpec/'):
            self._proxy()
        else:
            self.send_error(404, "Not Found")

    def do_PUT(self):
        if self.path.startswith('/api/acpec/'):
            self._proxy()
        else:
            self.send_error(404, "Not Found")

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'POST, GET, OPTIONS, PUT')
        self.send_header(
            'Access-Control-Allow-Headers',
            'Content-Type, Authorization, X-ACPEC-Mobile-Token, X-Acpec-Session, X-Odoo-Database, X-Requested-With',
        )
        self.send_header('Access-Control-Max-Age', '86400')
        self.end_headers()

    def _proxy(self):
        target_url = ODOO_ORIGIN.rstrip('/') + self.path
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length) if content_length > 0 else None

        headers = {
            k: v
            for k, v in self.headers.items()
            if k.lower() not in ('host', 'origin', 'referer')
        }
        headers['Host'] = urllib.parse.urlparse(ODOO_ORIGIN).netloc

        req = urllib.request.Request(
            target_url, data=body, headers=headers, method=self.command
        )
        try:
            with urllib.request.urlopen(req) as resp:
                self.send_response(resp.status)
                for k, v in resp.getheaders():
                    if k.lower() not in (
                        'transfer-encoding',
                        'content-encoding',
                        'content-length',
                        'access-control-allow-origin',
                    ):
                        self.send_header(k, v)
                self.send_header('Access-Control-Allow-Origin', '*')
                resp_data = resp.read()
                self.send_header('Content-Length', str(len(resp_data)))
                self.end_headers()
                self.wfile.write(resp_data)
        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            for k, v in e.headers.items():
                if k.lower() not in (
                    'transfer-encoding',
                    'content-encoding',
                    'content-length',
                    'access-control-allow-origin',
                ):
                    self.send_header(k, v)
            self.send_header('Access-Control-Allow-Origin', '*')
            err_data = e.read()
            self.send_header('Content-Length', str(len(err_data)))
            self.end_headers()
            self.wfile.write(err_data)
        except Exception as e:
            self.send_response(502)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(f'{{"ok": false, "error": "{e}"}}'.encode())


if __name__ == '__main__':
    server = ReusableHTTPServer(('0.0.0.0', PORT), ProxyHandler)
    print(f'LP E-Tickets web server: http://127.0.0.1:{PORT}')
    print(f'Proxying /api/acpec/* to {ODOO_ORIGIN}')
    server.serve_forever()
