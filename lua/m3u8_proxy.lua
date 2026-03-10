local http = require "resty.http"
local utils = require "utils"
local cjson = require "cjson.safe"
local access = require "access"

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

-- Check if URL looks like a segment (ts, m4s, aac, mp4, vtt, key, etc.)
local function is_segment_url(uri)
    local lower_uri = uri:lower()
    -- Common segment extensions
    if lower_uri:match("%.ts") then return true end
    if lower_uri:match("%.m4s") then return true end
    if lower_uri:match("%.m4a") then return true end
    if lower_uri:match("%.m4v") then return true end
    if lower_uri:match("%.mp4") then return true end
    if lower_uri:match("%.aac") then return true end
    if lower_uri:match("%.vtt") then return true end
    if lower_uri:match("%.webvtt") then return true end
    if lower_uri:match("%.srt") then return true end
    if lower_uri:match("%.key") then return true end
    -- Check for segment patterns in query params
    if lower_uri:match("segment") then return true end
    if lower_uri:match("/seg%-") then return true end
    if lower_uri:match("/chunk") then return true end
    return false
end

-- Determine proxy type - default to m3u8 unless it looks like a segment
local function get_proxy_type(uri)
    -- Explicit m3u8/m3u extension
    if uri:match("%.m3u8") or uri:match("%.m3u$") or uri:match("%.m3u%?") then
        return "m3u8-proxy"
    end
    -- Looks like a segment
    if is_segment_url(uri) then
        return "ts-proxy"
    end
    -- Default to m3u8 for unknown URLs (safer for playlists)
    return "m3u8-proxy"
end

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

-- Track if next line is a variant playlist URL (follows #EXT-X-STREAM-INF)
local next_is_variant = false

-- Process the M3U8 content line by line
local lines = {}
for line in content:gmatch("[^\r\n]+") do
    local processed_line = line

    if line ~= "" then
        -- Segment/Playlist URLs (not tags)
        if not line:match("^#") then
            local segment_url = utils.resolve_url(base_url, line)
            local proxy_type
            if next_is_variant then
                -- After #EXT-X-STREAM-INF, always a playlist
                proxy_type = "m3u8-proxy"
                next_is_variant = false
            else
                -- Use detection for segments in media playlists
                proxy_type = get_proxy_type(line)
            end
            processed_line = utils.build_proxy_url(segment_url, headers, proxy_type)

        -- Variant stream info (next line is playlist URL)
        elseif line:match("^#EXT%-X%-STREAM%-INF") then
            next_is_variant = true

        -- Encryption keys
        elseif line:match("^#EXT%-X%-KEY") then
            processed_line = rewrite_uri_attr(line, "ts-proxy")

        -- Session keys
        elseif line:match("^#EXT%-X%-SESSION%-KEY") then
            processed_line = rewrite_uri_attr(line, "ts-proxy")

        -- Init segments (fMP4)
        elseif line:match("^#EXT%-X%-MAP") then
            processed_line = rewrite_uri_attr(line, "ts-proxy")

        -- I-Frame playlists (always m3u8)
        elseif line:match("^#EXT%-X%-I%-FRAME%-STREAM%-INF") then
            processed_line = rewrite_uri_attr(line, "m3u8-proxy")

        -- Alternate renditions (audio/subtitles - always m3u8 playlists)
        elseif line:match("^#EXT%-X%-MEDIA") then
            processed_line = rewrite_uri_attr(line, "m3u8-proxy")

        -- LL-HLS: Partial segments
        elseif line:match("^#EXT%-X%-PART:") then
            processed_line = rewrite_uri_attr(line, "ts-proxy")

        -- LL-HLS: Preload hints
        elseif line:match("^#EXT%-X%-PRELOAD%-HINT") then
            processed_line = rewrite_uri_attr(line, "ts-proxy")

        -- LL-HLS: Rendition reports (m3u8)
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
