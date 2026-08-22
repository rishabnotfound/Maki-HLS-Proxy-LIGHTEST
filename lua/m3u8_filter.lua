local utils = require "utils"

local chunk = ngx.arg[1]
local eof = ngx.arg[2]

local buf = ngx.ctx.m3u8_buf or {}
if chunk and chunk ~= "" then
    buf[#buf + 1] = chunk
end
ngx.ctx.m3u8_buf = buf

if not eof then
    ngx.arg[1] = nil
    return
end

local content = table.concat(buf)
local url = ngx.ctx.upstream_url
local headers = ngx.ctx.upstream_headers or {}

if not url then
    ngx.arg[1] = content
    return
end

local base_url = utils.get_base_url(url)

local function rewrite_uri_attr(line, proxy_type)
    local uri = line:match('URI="([^"]+)"')
    if uri then
        local abs_url = utils.resolve_url(base_url, uri)
        local proxied = utils.build_proxy_url(abs_url, headers, proxy_type)
        local escaped_proxied = proxied:gsub("%%", "%%%%")
        return line:gsub('URI="[^"]+"', 'URI="' .. escaped_proxied .. '"')
    end
    return line
end

local next_line_type = nil
local lines = {}

for line in content:gmatch("[^\r\n]+") do
    local processed_line = line

    if line ~= "" then
        if not line:match("^#") then
            local abs_url = utils.resolve_url(base_url, line)
            local proxy_type
            if next_line_type == "segment" then
                proxy_type = "ts-proxy"
            elseif next_line_type == "playlist" then
                proxy_type = "m3u8-proxy"
            else
                if line:match("%.ts") or line:match("%.m4s") or line:match("%.aac") or line:match("%.mp4") or line:match("%.vtt") then
                    proxy_type = "ts-proxy"
                else
                    proxy_type = "m3u8-proxy"
                end
            end
            processed_line = utils.build_proxy_url(abs_url, headers, proxy_type)
            next_line_type = nil
        elseif line:match("^#EXTINF") then
            next_line_type = "segment"
        elseif line:match("^#EXT%-X%-STREAM%-INF") then
            next_line_type = "playlist"
        elseif line:match("^#EXT%-X%-KEY") then
            processed_line = rewrite_uri_attr(line, "ts-proxy")
        elseif line:match("^#EXT%-X%-SESSION%-KEY") then
            processed_line = rewrite_uri_attr(line, "ts-proxy")
        elseif line:match("^#EXT%-X%-MAP") then
            processed_line = rewrite_uri_attr(line, "ts-proxy")
        elseif line:match("^#EXT%-X%-I%-FRAME%-STREAM%-INF") then
            processed_line = rewrite_uri_attr(line, "m3u8-proxy")
        elseif line:match("^#EXT%-X%-MEDIA") then
            processed_line = rewrite_uri_attr(line, "m3u8-proxy")
        elseif line:match("^#EXT%-X%-PART:") then
            processed_line = rewrite_uri_attr(line, "ts-proxy")
        elseif line:match("^#EXT%-X%-PRELOAD%-HINT") then
            processed_line = rewrite_uri_attr(line, "ts-proxy")
        elseif line:match("^#EXT%-X%-RENDITION%-REPORT") then
            processed_line = rewrite_uri_attr(line, "m3u8-proxy")
        elseif line:match("^#EXT%-X%-BYTERANGE") then
            next_line_type = "segment"
        end
    end

    lines[#lines + 1] = processed_line
end

ngx.arg[1] = table.concat(lines, "\n")
