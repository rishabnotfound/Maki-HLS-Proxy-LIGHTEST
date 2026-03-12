const PROXY_HOST = 'http://localhost:80';

// Edit these values
const url = 'https://skyember44.online/file2/8tyfuM8m1kJQmky96U8SfXnnSU0LtudmVQzA63XcIYwK3hYSNhl73sdOcOeY5IGx4~9cpMK3UghGhURm8~9aSYQrtJwDfPrAdv2IZBDYu5lEYOPp2PP+5hPedBsb76y2RYHoGGxSG~xwYhMvHlTpsKRNAs3sRMtghnHlHdA84xg=/cGxheWxpc3QubTN1OA==.m3u8';
const headers = { 
  "Origin" : "https://videostr.net", 
  "Referer": "https://videostr.net/",
  "Host": "skyember44.online"
};

const proxyUrl = `${PROXY_HOST}/m3u8-proxy.m3u8?url=${encodeURIComponent(url)}&headers=${encodeURIComponent(JSON.stringify(headers))}`;

console.log(proxyUrl);
