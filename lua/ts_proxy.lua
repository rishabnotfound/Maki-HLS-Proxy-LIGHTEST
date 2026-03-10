local http = require "resty.http"
local utils = require "utils"

-- Get query parameters
local args = ngx.req.get_uri_args()
local url = utils.url_decode(args.url)
local headers = utils.parse_headers(args.headers)

if not url then
    ngx.status = 400
    ngx.say('{"error": "Missing url parameter"}')
    return ngx.exit(400)
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
local range = ngx.var.http_range
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

-- Set response headers
ngx.status = res.status

-- Forward content type
local content_type = res.headers["Content-Type"]
if content_type then
    ngx.header["Content-Type"] = content_type
else
    -- Guess based on URL
    if url:match("%.ts$") or url:match("%.ts%?") then
        ngx.header["Content-Type"] = "video/mp2t"
    elseif url:match("%.m4s$") or url:match("%.m4s%?") then
        ngx.header["Content-Type"] = "video/iso.segment"
    elseif url:match("%.key$") or url:match("%.key%?") then
        ngx.header["Content-Type"] = "application/octet-stream"
    else
        ngx.header["Content-Type"] = "application/octet-stream"
    end
end

-- Forward content length
if res.headers["Content-Length"] then
    ngx.header["Content-Length"] = res.headers["Content-Length"]
end

-- Forward content range for partial content
if res.headers["Content-Range"] then
    ngx.header["Content-Range"] = res.headers["Content-Range"]
end

-- Cache headers
ngx.header["Cache-Control"] = "public, max-age=86400"

ngx.print(res.body)
