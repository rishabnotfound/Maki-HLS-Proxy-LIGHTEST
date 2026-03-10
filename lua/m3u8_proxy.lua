local http = require "resty.http"
local utils = require "utils"
local cjson = require "cjson.safe"

-- Get query parameters
local args = ngx.req.get_uri_args()
local url = utils.url_decode(args.url)
local headers = utils.parse_headers(args.headers)

if not url then
    ngx.status = 400
    ngx.say('{"error": "Missing url parameter"}')
    return ngx.exit(400)
end

ngx.log(ngx.INFO, "Fetching M3U8: ", url)

-- Create HTTP client
local httpc = http.new()
httpc:set_timeout(10000)

-- Build request headers
local req_headers = {
    ["User-Agent"] = headers["User-Agent"] or "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
    ["Accept"] = "*/*",
}

-- Merge custom headers
for k, v in pairs(headers) do
    req_headers[k] = v
end

-- Fetch the M3U8 playlist
local res, err = httpc:request_uri(url, {
    method = "GET",
    headers = req_headers,
    ssl_verify = false,
})

if not res then
    ngx.log(ngx.ERR, "Failed to fetch M3U8: ", err)
    ngx.status = 502
    ngx.say('{"error": "Failed to fetch playlist: ' .. (err or "unknown") .. '"}')
    return ngx.exit(502)
end

if res.status ~= 200 then
    ngx.log(ngx.ERR, "M3U8 returned status: ", res.status)
    ngx.status = res.status
    ngx.say(res.body)
    return ngx.exit(res.status)
end

local content = res.body
local base_url = utils.get_base_url(url)

-- Helper: rewrite URI attribute in a line
local function rewrite_uri_attr(line, proxy_type)
    local uri = line:match('URI="([^"]+)"')
    if uri then
        local abs_url = utils.resolve_url(base_url, uri)
        local proxied = utils.build_proxy_url(abs_url, headers, proxy_type)
        -- Escape special chars in replacement
        local escaped_proxied = proxied:gsub("%%", "%%%%")
        return line:gsub('URI="[^"]+"', 'URI="' .. escaped_proxied .. '"')
    end
    return line
end

-- Process the M3U8 content line by line
local lines = {}
for line in content:gmatch("[^\r\n]+") do
    local processed_line = line

    if line ~= "" then
        -- Segment URLs (not tags)
        if not line:match("^#") then
            local segment_url = utils.resolve_url(base_url, line)
            local proxy_type = "ts-proxy"
            if line:match("%.m3u8") or line:match("%.m3u$") then
                proxy_type = "m3u8-proxy"
            end
            processed_line = utils.build_proxy_url(segment_url, headers, proxy_type)

        -- Encryption keys
        elseif line:match("^#EXT%-X%-KEY") then
            processed_line = rewrite_uri_attr(line, "ts-proxy")

        -- Session keys
        elseif line:match("^#EXT%-X%-SESSION%-KEY") then
            processed_line = rewrite_uri_attr(line, "ts-proxy")

        -- Init segments (fMP4)
        elseif line:match("^#EXT%-X%-MAP") then
            processed_line = rewrite_uri_attr(line, "ts-proxy")

        -- I-Frame playlists (point to m3u8)
        elseif line:match("^#EXT%-X%-I%-FRAME%-STREAM%-INF") then
            processed_line = rewrite_uri_attr(line, "m3u8-proxy")

        -- Alternate renditions (audio/subtitles/video)
        elseif line:match("^#EXT%-X%-MEDIA") then
            local uri = line:match('URI="([^"]+)"')
            if uri then
                local proxy_type = "ts-proxy"
                if uri:match("%.m3u8") or uri:match("%.m3u$") then
                    proxy_type = "m3u8-proxy"
                end
                processed_line = rewrite_uri_attr(line, proxy_type)
            end

        -- LL-HLS: Partial segments
        elseif line:match("^#EXT%-X%-PART:") then
            processed_line = rewrite_uri_attr(line, "ts-proxy")

        -- LL-HLS: Preload hints
        elseif line:match("^#EXT%-X%-PRELOAD%-HINT") then
            processed_line = rewrite_uri_attr(line, "ts-proxy")

        -- LL-HLS: Rendition reports (for blocking playlist reload)
        elseif line:match("^#EXT%-X%-RENDITION%-REPORT") then
            processed_line = rewrite_uri_attr(line, "m3u8-proxy")
        end
    end

    table.insert(lines, processed_line)
end

local result = table.concat(lines, "\n")

-- Set response headers
ngx.header["Content-Type"] = "application/vnd.apple.mpegurl"
ngx.header["Cache-Control"] = "no-cache"

ngx.say(result)
