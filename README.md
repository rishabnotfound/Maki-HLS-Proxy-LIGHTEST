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

## Routes

```
GET /m3u8-proxy.m3u8?url={encoded}&headers={encoded}
GET /ts-proxy.ts?url={encoded}&headers={encoded}
GET /mp4-proxy.mp4?url={encoded}&headers={encoded}
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