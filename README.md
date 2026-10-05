<p align="center">
      <img
        src="./public/logo.png"
        width="200"
        height="200"
      />
</p>

# <p align="center">Maki-HLS-Proxy-LIGHTEST</p>

The **fastest** and **lightest** HLS proxy. Pure Nginx + Lua. No Node.js, no Python, no bloat.

~15MB Docker image. Handles thousands of concurrent streams.

## Why?

| | Node.js Proxy | This |
|--|---------------|------|
| Image Size | ~200MB+ | ~15MB |
| Memory | 50-100MB+ | ~5MB |
| Dependencies | node_modules hell | Zero |
| Speed | JavaScript | C + LuaJIT |

## Install Docker (if needed)

```bash
# Ubuntu/Debian
sudo apt update && sudo apt install snapd -y
sudo snap install docker
```

## Quick Start

```bash
git clone https://github.com/rishabnotfound/maki-hls-proxy-lightest.git
cd maki-hls-proxy-lightest
docker compose up -d --build
```

That's it. Running on port 80.

## Deploy with Cloudflare (Free SSL + CDN)

No CloudPanel, no Nginx config, no certbot. Just:

1. Get a VPS (any cheap one works)
2. Run the Quick Start commands above
3. In Cloudflare, add an **A record** pointing to your VPS IP

Done. Cloudflare handles SSL automatically. The proxy auto-detects your domain from requests.

## Direct Domain (no Cloudflare) with Auto TLS

If someone points a domain straight at your host (bypassing CF), the proxy can grab a free Let's Encrypt cert automatically.

1. Point your domain's **A record** at the host IP. Port 80 must be reachable (needed for cert issuance).
2. In `.env`:
   ```env
   DOMAIN=yourdomain.com
   LETSENCRYPT_EMAIL=you@example.com
   ```
3. `docker compose up -d --build`

First boot issues the cert, nginx reloads with HTTPS on :443, and a background loop renews every 12h. Certs persist in `./letsencrypt/`.

Leave `DOMAIN` empty = HTTP-only (same as before, for the CF path).

## Routes

```
GET /m3u8-proxy.m3u8?url={encoded}&headers={encoded}
GET /ts-proxy.ts?url={encoded}&headers={encoded}
GET /mp4-proxy.mp4?url={encoded}&headers={encoded}
```

Or, with encryption enabled (see below):

```
GET /m3u8-proxy.m3u8?p={encrypted_token}
GET /ts-proxy.ts?p={encrypted_token}
GET /mp4-proxy.mp4?p={encrypted_token}
```

## Usage

### Plain (default)

```javascript
const proxy = 'https://proxy.yourdomain.com';
const url = encodeURIComponent('https://example.com/stream.m3u8');
const headers = encodeURIComponent(JSON.stringify({
  'Referer': 'https://example.com',
  'Origin': 'https://example.com'
}));

fetch(`${proxy}/m3u8-proxy.m3u8?url=${url}&headers=${headers}`);
```

### Encrypted (when `ENCRYPTION_KEY` is set)

```javascript
const crypto = require('crypto');

const KEY = '<same 64-hex key set on the proxy>';

function b64url(buf) {
  return buf.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function encryptPayload(url, headers, keyHex) {
  const key = Buffer.from(keyHex, 'hex');
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv('aes-256-cbc', key, iv);
  const json = JSON.stringify({ u: url, h: headers });
  const ct = Buffer.concat([cipher.update(json, 'utf8'), cipher.final()]);
  return b64url(Buffer.concat([iv, ct]));
}

const token = encryptPayload(
  'https://example.com/stream.m3u8',
  { Referer: 'https://example.com', Origin: 'https://example.com' },
  KEY
);

fetch(`${proxy}/m3u8-proxy.m3u8?p=${encodeURIComponent(token)}`);
```

Full runnable example: see `test.js`.

## Features

- Master/Variant playlists
- TS/fMP4 segments
- AES-128 encrypted streams
- LL-HLS (Low-Latency)
- Alternate audio/subtitles
- I-Frame playlists
- **MP4 proxy** (true streaming, minimal memory)
- Origin protection (`allowed_origins.txt`)
- CORS with credentials
- Segment caching (configurable)

## Cache Settings

Uses **nginx native `proxy_cache`** - fast, efficient, zero CPU overhead.

Edit `.env` to configure:

```env
# Cache size (set to 0 to disable)
CACHE_SIZE=5g

# Delete cached files not accessed within this time
CACHE_EXPIRY=12h
```

Options: `1g`, `5g`, `10g`, `20g` | `30m`, `1h`, `12h`, `1d`, `7d`

- **max_size** - Oldest files auto-deleted when full (LRU)
- **inactive** - Files not accessed within this time are deleted
- Cache persists in `./maki-hls-proxy-cache/`

## URL Encryption (optional)

Hide the target URL and headers from anyone inspecting requests. Off by default. Only your scraper and the proxy hold the key — anyone snooping the proxy URL sees an opaque token.

### Turning it on

**1. Generate a key** (64 hex chars = 32 bytes):

```bash
openssl rand -hex 32
```

**2. Add it to `.env`** (same file as `CACHE_SIZE`):

```env
ENCRYPTION_KEY=<the 64-hex string from step 1>
```

**3. Rebuild:**

```bash
docker compose up -d --build
```

You'll see `Encryption: ENABLED (AES-256-CBC)` in the startup logs.

**4. Use the same key in your scraper** (see the "Encrypted" example under [Usage](#usage)).

### Turning it off

Remove the `ENCRYPTION_KEY` line from `.env` and rebuild. Plain `?url=&headers=` URLs always work either way (backwards compatible).

### How it works

- Clients encrypt `{u: url, h: headers}` (JSON) with **AES-256-CBC**, prepend the 16-byte IV, base64url-encode.
- Send as `?p=<token>` instead of `?url=&headers=`.
- The proxy rewrites segment URLs in m3u8 playlists to also use `?p=`, so the entire chain stays opaque.
- Bad/missing key → 400. Key length must be exactly 64 hex chars or encryption is disabled with a warning.

## Origin Protection

Edit `allowed_origins.txt`:
```
localhost
yourdomain.com
https://app.example.com
```

Rebuild after changes.

## License

[MIT](LICENSE) — do whatever you want, i know exactly what you're using this for 🥀

## Credits

Built by [rishabnotfound](https://github.com/rishabnotfound)