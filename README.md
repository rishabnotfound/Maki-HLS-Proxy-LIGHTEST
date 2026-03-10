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
4. Edit `.env` and set your domain:

```env
PROXY_HOST=https://proxy.yourdomain.com
```

5. Restart:

```bash
docker compose up -d --build
```

Done. Cloudflare handles SSL automatically.

## Routes

```
GET /m3u8-proxy.m3u8?url={encoded}&headers={encoded}
GET /ts-proxy.ts?url={encoded}&headers={encoded}
```

## Usage

```javascript
const proxy = 'https://proxy.yourdomain.com';
const url = encodeURIComponent('https://example.com/stream.m3u8');
const headers = encodeURIComponent(JSON.stringify({
  'Referer': 'https://example.com',
  'Origin': 'https://example.com'
}));

fetch(`${proxy}/m3u8-proxy.m3u8?url=${url}&headers=${headers}`);
```

## Features

- Master/Variant playlists
- TS/fMP4 segments
- AES-128 encrypted streams
- LL-HLS (Low-Latency)
- Alternate audio/subtitles
- I-Frame playlists
- Origin protection (`allowed_origins.txt`)
- CORS with credentials
- Segment caching (configurable)

## Cache Settings

Edit `.env` to configure caching:

```env
# Cache size (set to 0 to disable)
CACHE_SIZE=10g

# Auto-delete cache after this time
CACHE_EXPIRY=2d
```

Options: `1g`, `5g`, `10g`, `20g` | `1d`, `12h`, `7d`

When cache is full, oldest items are automatically removed. Cache persists across restarts.

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
