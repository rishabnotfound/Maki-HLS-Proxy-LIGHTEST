# Nginx HLS Proxy

A lightweight HLS proxy built with OpenResty (Nginx + Lua).

## Routes

### `/m3u8-proxy`
Proxies M3U8 playlists and rewrites segment URLs to route through the proxy.

### `/ts-proxy`
Proxies TS segments, encryption keys, and init segments.

## Query Parameters

| Parameter | Description |
|-----------|-------------|
| `url` | URL-encoded target URL |
| `headers` | URL-encoded JSON object of headers |

## Usage

### Build & Run

```bash
docker compose up -d --build
```

### Example Request

```bash
# Basic playlist proxy
curl "http://localhost:8080/m3u8-proxy?url=https%3A%2F%2Fexample.com%2Fstream.m3u8"

# With custom headers
curl "http://localhost:8080/m3u8-proxy?url=https%3A%2F%2Fexample.com%2Fstream.m3u8&headers=%7B%22Referer%22%3A%22https%3A%2F%2Fexample.com%22%7D"
```

### JavaScript Example

```javascript
const url = 'https://example.com/stream.m3u8';
const headers = {
  'Referer': 'https://example.com',
  'Origin': 'https://example.com'
};

const proxyUrl = `http://localhost:8080/m3u8-proxy?url=${encodeURIComponent(url)}&headers=${encodeURIComponent(JSON.stringify(headers))}`;
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PROXY_HOST` | `http://localhost:8080` | Public URL of the proxy (used for rewriting URLs) |

## Production

For production, set `PROXY_HOST` to your public URL:

```bash
PROXY_HOST=https://proxy.example.com docker compose up -d
```
