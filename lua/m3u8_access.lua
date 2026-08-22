local utils = require "utils"
local access = require "access"
local cjson = require "cjson.safe"

if ngx.req.get_method() == "OPTIONS" then
    access.handle_options()
    return ngx.exit(204)
end

if not access.check() then
    access.deny()
    return ngx.exit(403)
end

local url, headers, err = utils.resolve_request()
if not url then
    ngx.status = 400
    ngx.say('{"error": "' .. (err or "bad request") .. '"}')
    return ngx.exit(400)
end

local target_host = url:match("https?://([^/]+)")

ngx.var.target_url = url
ngx.var.custom_host = headers["Host"] or headers["host"] or target_host or ""
ngx.var.custom_referer = headers["Referer"] or headers["referer"] or ""
ngx.var.custom_origin = headers["Origin"] or headers["origin"] or ""
ngx.var.custom_ua = headers["User-Agent"] or headers["user-agent"] or "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
ngx.var.custom_cookie = headers["Cookie"] or headers["cookie"] or ""
ngx.var.custom_auth = headers["Authorization"] or headers["authorization"] or ""
ngx.var.custom_accept = headers["Accept"] or headers["accept"] or "*/*"
ngx.var.custom_accept_lang = headers["Accept-Language"] or headers["accept-language"] or "en-US,en;q=0.9"
ngx.var.custom_xff = headers["X-Forwarded-For"] or headers["x-forwarded-for"] or ngx.var.remote_addr

ngx.ctx.upstream_url = url
ngx.ctx.upstream_headers = headers
