const PROXY_HOST = 'http://157.250.198.102/';

// Edit these values
const url = 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8';
const headers = { 
  "Origin" : "https://test-streams.mux.dev", 
  "Referer": "https://test-streams.mux.dev/" 
};

const proxyUrl = `${PROXY_HOST}/m3u8-proxy.m3u8?url=${encodeURIComponent(url)}&headers=${encodeURIComponent(JSON.stringify(headers))}`;

console.log(proxyUrl);
