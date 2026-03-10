local _M = {}

local cjson = require "cjson.safe"

-- URL decode
function _M.url_decode(str)
    if not str then return nil end
    str = string.gsub(str, "+", " ")
    str = string.gsub(str, "%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end)
    return str
end

-- URL encode
function _M.url_encode(str)
    if not str then return "" end
    str = string.gsub(str, "([^%w%-%.%_%~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    return str
end

-- Parse headers from JSON string
function _M.parse_headers(headers_param)
    if not headers_param or headers_param == "" then
        return {}
    end

    local decoded = _M.url_decode(headers_param)
    local headers, err = cjson.decode(decoded)

    if err then
        ngx.log(ngx.ERR, "Failed to parse headers JSON: ", err)
        return {}
    end

    return headers or {}
end

-- Get base URL (directory) from a full URL - strips filename, no trailing slash
function _M.get_base_url(url)
    -- Remove query string and fragment first
    local clean_url = url:match("^([^?#]+)") or url
    -- Find last slash and return everything before it (excluding the slash)
    local base = clean_url:match("^(.*)/[^/]*$")
    return base or clean_url
end

-- Resolve relative URL to absolute
function _M.resolve_url(base_url, relative_url)
    -- Already absolute
    if relative_url:match("^https?://") then
        return relative_url
    end

    -- Protocol relative
    if relative_url:match("^//") then
        local protocol = base_url:match("^(https?):")
        return protocol .. ":" .. relative_url
    end

    -- Absolute path (starts with /)
    if relative_url:match("^/") then
        local origin = base_url:match("^(https?://[^/]+)")
        return origin .. relative_url
    end

    -- Relative path - append to base_url directory
    -- base_url should already be a directory (no trailing slash)
    return base_url .. "/" .. relative_url
end

-- Build proxy URL for segments
function _M.build_proxy_url(original_url, headers, proxy_type)
    local proxy_host = os.getenv("PROXY_HOST") or "http://localhost:8080"
    local encoded_url = _M.url_encode(original_url)
    local encoded_headers = _M.url_encode(cjson.encode(headers))

    -- Map proxy type to endpoint with extension
    local endpoint = "ts-proxy.ts"
    if proxy_type == "m3u8-proxy" then
        endpoint = "m3u8-proxy.m3u8"
    end

    return string.format("%s/%s?url=%s&headers=%s",
        proxy_host, endpoint, encoded_url, encoded_headers)
end

return _M
