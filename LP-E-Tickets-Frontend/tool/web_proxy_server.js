const fs = require('fs');
const http = require('http');
const path = require('path');

const port = Number(process.env.PORT || 8091);
const odooOrigin = process.env.ODOO_ORIGIN || 'http://57.128.181.183:8199';
const webRoot = path.resolve(__dirname, '..', 'build', 'web');

const contentTypes = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.wasm': 'application/wasm',
};

function sendFile(res, filePath) {
  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
      res.end('Not found');
      return;
    }
    const ext = path.extname(filePath).toLowerCase();
    res.writeHead(200, {
      'content-type': contentTypes[ext] || 'application/octet-stream',
      'cache-control': 'no-store',
    });
    res.end(data);
  });
}

function proxyToOdoo(req, res) {
  const target = new URL(req.url, odooOrigin);
  const headers = { ...req.headers, host: target.host };
  delete headers.origin;
  delete headers.referer;

  const proxyReq = http.request(
    target,
    {
      method: req.method,
      headers,
    },
    (proxyRes) => {
      const outHeaders = { ...proxyRes.headers };
      outHeaders['access-control-allow-origin'] = '*';
      res.writeHead(proxyRes.statusCode || 502, outHeaders);
      proxyRes.pipe(res);
    },
  );

  proxyReq.on('error', (err) => {
    res.writeHead(502, { 'content-type': 'application/json; charset=utf-8' });
    res.end(JSON.stringify({ ok: false, error: err.message }));
  });

  req.pipe(proxyReq);
}

const server = http.createServer((req, res) => {
  if (req.url.startsWith('/api/acpec/')) {
    proxyToOdoo(req, res);
    return;
  }

  const urlPath = decodeURIComponent(req.url.split('?')[0]);
  const cleanPath = urlPath === '/' ? '/index.html' : urlPath;
  const filePath = path.normalize(path.join(webRoot, cleanPath));
  if (!filePath.startsWith(webRoot)) {
    res.writeHead(403);
    res.end('Forbidden');
    return;
  }

  if (fs.existsSync(filePath) && fs.statSync(filePath).isFile()) {
    sendFile(res, filePath);
    return;
  }
  sendFile(res, path.join(webRoot, 'index.html'));
});

server.listen(port, '0.0.0.0', () => {
  console.log(`LP E-Tickets web proxy: http://0.0.0.0:${port}`);
  console.log(`Proxying /api/acpec/* to ${odooOrigin}`);
});
