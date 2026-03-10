const PROXY_HOST = 'http://localhost:80';

// Edit these values
const url = 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8';
const headers = { 
  "Origin" : "https://google.com", 
  "Referer": "https://google.com/" 
};

const proxyUrl = `${PROXY_HOST}/m3u8-proxy.m3u8?url=${encodeURIComponent(url)}&headers=${encodeURIComponent(JSON.stringify(headers))}`;

console.log(proxyUrl);
