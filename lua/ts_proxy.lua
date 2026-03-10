local http = require "resty.http"
local utils = require "utils"
local access = require "access"
local cache = require "cache"

-- Handle OPTIONS preflight
if ngx.req.get_method() == "OPTIONS" then
    return access.handle_options()
end

-- Check origin
if not access.check() then
    return access.deny()
end

-- Set CORS headers for response
access.set_cors_headers()

-- Get query parameters
local args = ngx.req.get_uri_args()
local url = utils.url_decode(args.url)
local headers = utils.parse_headers(args.headers)

if not url then
    ngx.status = 400
    ngx.say('{"error": "Missing url parameter"}')
    return ngx.exit(400)
end

-- Check for range request (don't cache partial requests)
local range = ngx.var.http_range
local use_cache = not range

-- Try cache first (only for full requests, not range/partial)
if use_cache then
    local cached = cache.get(url)
    if cached then
        ngx.header["Content-Type"] = cached.content_type
        ngx.header["Content-Length"] = #cached.body
        ngx.header["X-Cache-Status"] = "HIT"
        ngx.header["Cache-Control"] = "public, max-age=86400"
        ngx.print(cached.body)
        return
    end
end

ngx.log(ngx.INFO, "Fetching segment: ", url)

-- Create HTTP client
local httpc = http.new()
httpc:set_timeout(30000)

-- Build request headers
local req_headers = {
    ["User-Agent"] = headers["User-Agent"] or "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
    ["Accept"] = "*/*",
}

-- Merge custom headers
for k, v in pairs(headers) do
    req_headers[k] = v
end

-- Support range requests
if range then
    req_headers["Range"] = range
end

-- Fetch the segment
local res, err = httpc:request_uri(url, {
    method = "GET",
    headers = req_headers,
    ssl_verify = false,
})

if not res then
    ngx.log(ngx.ERR, "Failed to fetch segment: ", err)
    ngx.status = 502
    ngx.say('{"error": "Failed to fetch segment: ' .. (err or "unknown") .. '"}')
    return ngx.exit(502)
end

if res.status ~= 200 and res.status ~= 206 then
    ngx.log(ngx.ERR, "Segment returned status: ", res.status)
    ngx.status = res.status
    ngx.say(res.body)
    return ngx.exit(res.status)
end

-- Determine content type
local content_type = res.headers["Content-Type"]
if not content_type then
    if url:match("%.ts") then
        content_type = "video/mp2t"
    elseif url:match("%.m4s") then
        content_type = "video/iso.segment"
    elseif url:match("%.m4a") then
        content_type = "audio/mp4"
    elseif url:match("%.vtt") then
        content_type = "text/vtt"
    else
        content_type = "application/octet-stream"
    end
end

-- Cache the response (only full 200 responses, not 206 partial)
if use_cache and res.status == 200 then
    cache.set(url, content_type, res.body)
end

-- Set response headers
ngx.status = res.status
ngx.header["Content-Type"] = content_type
ngx.header["X-Cache-Status"] = use_cache and "MISS" or "BYPASS"
ngx.header["Cache-Control"] = "public, max-age=86400"

if res.headers["Content-Length"] then
    ngx.header["Content-Length"] = res.headers["Content-Length"]
end

if res.headers["Content-Range"] then
    ngx.header["Content-Range"] = res.headers["Content-Range"]
end

ngx.print(res.body)
