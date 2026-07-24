/**
 * ZEA Internal HTTP client — uses Node.js http/https module.
 * Unlike fetch (undici), this delegates DNS resolution to the OS
 * and respects /etc/hosts, Docker DNS, and .localhost domains.
 *
 * Usage: same as fetch but guaranteed to resolve local hostnames.
 *   import { zeaFetch } from '../lib/http.js';
 *   const resp = await zeaFetch(url, { method:'POST', body: data, headers: {...} });
 *   const json = await resp.json();
 */
import http from 'http';
import https from 'https';
import { URL } from 'url';

export class ZeaError extends Error {
  constructor(message, { status, code, url } = {}) {
    super(message);
    this.name = 'ZeaError';
    this.status = status;
    this.code = code;
    this.url = url;
  }
}

const isDebug = () => process.argv.includes('--debug') || process.argv.includes('-d');

export function zeaFetch(url, options = {}) {
  const startTime = Date.now();
  const method = options.method || 'GET';

  return new Promise((resolve, reject) => {
    const parsed = new URL(url);
    const isHttps = parsed.protocol === 'https:';
    const mod = isHttps ? https : http;
    const port = parsed.port || (isHttps ? 443 : 80);

    // Resolve .zea.localhost → 127.0.0.1 without monkey-patching global DNS
    const hostname =
      parsed.hostname === 'zea.localhost' || parsed.hostname.endsWith('.zea.localhost')
        ? '127.0.0.1'
        : parsed.hostname;

    // Preserve original hostname for Caddy routing when resolving to 127.0.0.1
    const headers = { ...(options.headers || {}) };
    if (hostname === '127.0.0.1' && parsed.hostname !== '127.0.0.1') {
      headers['Host'] = parsed.hostname;
    }

    const reqOptions = {
      hostname,
      port: port,
      path: parsed.pathname + parsed.search,
      method: method,
      headers,
      timeout: options.timeout || 30000,
    };

    if (isDebug()) {
      const bodyPreview = options.body
        ? typeof options.body === 'string'
          ? options.body.slice(0, 200)
          : JSON.stringify(options.body).slice(0, 200)
        : '';
      console.error(
        `\x1b[2m[DEBUG] ${method} ${url}${bodyPreview ? '\n       body: ' + bodyPreview : ''}\x1b[0m`,
      );
    }

    const req = mod.request(reqOptions, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => {
        const elapsed = Date.now() - startTime;
        if (isDebug()) {
          const icon = res.statusCode >= 200 && res.statusCode < 400 ? '✅' : '❌';
          console.error(
            `\x1b[2m[DEBUG] ← ${icon} ${res.statusCode} (${elapsed}ms)${data ? ' body: ' + data.slice(0, 300) : ''}\x1b[0m`,
          );
        }
        resolve({
          ok: res.statusCode >= 200 && res.statusCode < 400,
          status: res.statusCode,
          statusText: res.statusMessage,
          headers: res.headers,
          json: async () => {
            try {
              return JSON.parse(data);
            } catch (e) {
              throw new Error(`Invalid JSON: ${data.slice(0, 100)}`, { cause: e });
            }
          },
          text: async () => data,
        });
      });
    });

    req.on('error', (e) => {
      if (isDebug()) console.error(`\x1b[2m[DEBUG] ← ❌ ERROR: ${e.message}\x1b[0m`);
      reject(new ZeaError(e.message, { code: e.code, url }));
    });
    req.setTimeout(options.timeout || 30000, () => {
      req.destroy();
      reject(new ZeaError('Request timed out', { code: 'ETIMEDOUT', url }));
    });

    if (options.body) {
      if (typeof options.body === 'string') {
        req.write(options.body);
      } else if (Buffer.isBuffer(options.body)) {
        req.write(options.body);
      } else {
        req.write(JSON.stringify(options.body));
      }
    }
    req.end();
  });
}

export default zeaFetch;
