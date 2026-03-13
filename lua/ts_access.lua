local utils = require "utils"
local access = require "access"

-- Handle OPTIONS preflight
if ngx.req.get_method() == "OPTIONS" then
    access.handle_options()
    return ngx.exit(204)
end

-- Check origin
if not access.check() then
    access.deny()
    return ngx.exit(403)
end

-- Get query parameters
local args = utils.parse_query_params()
local url = utils.url_decode(args.url)
local headers = utils.parse_headers(args.headers)

if not url then
    ngx.status = 400
    ngx.say('{"error": "Missing url parameter"}')
    return ngx.exit(400)
end

-- Extract host from target URL for default
local target_host = url:match("https?://([^/]+)")

-- Set variables for proxy_pass
ngx.var.target_url = url
ngx.var.custom_host = headers["Host"] or headers["host"] or target_host or ""
ngx.var.custom_referer = headers["Referer"] or headers["referer"] or ""
ngx.var.custom_origin = headers["Origin"] or headers["origin"] or ""
ngx.var.custom_ua = headers["User-Agent"] or headers["user-agent"] or "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
ngx.var.custom_cookie = headers["Cookie"] or headers["cookie"] or ""
ngx.var.custom_auth = headers["Authorization"] or headers["authorization"] or ""
ngx.var.custom_accept = headers["Accept"] or headers["accept"] or "*/*"
ngx.var.custom_accept_lang = headers["Accept-Language"] or headers["accept-language"] or ""
ngx.var.custom_accept_enc = headers["Accept-Encoding"] or headers["accept-encoding"] or ""
ngx.var.custom_xff = headers["X-Forwarded-For"] or headers["x-forwarded-for"] or ngx.var.remote_addr
-- Use browser's Range header first (for video seeking), then fallback to query param
ngx.var.custom_range = ngx.var.http_range or headers["Range"] or headers["range"] or ""
