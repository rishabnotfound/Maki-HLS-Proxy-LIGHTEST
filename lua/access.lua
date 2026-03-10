local _M = {}

local allowed_origins = {}
local loaded = false

-- Load allowed origins from file
local function load_origins()
    if loaded then return end

    local file = io.open("/usr/local/openresty/nginx/allowed_origins.txt", "r")
    if not file then
        ngx.log(ngx.ERR, "allowed_origins.txt not found")
        loaded = true
        return
    end

    for line in file:lines() do
        -- Skip comments and empty lines
        line = line:match("^%s*(.-)%s*$") -- trim
        if line ~= "" and not line:match("^#") then
            -- Extract hostname if full URL provided (https://example.com -> example.com)
            local host = line:match("^https?://([^/:]+)") or line
            allowed_origins[host:lower()] = true
        end
    end

    file:close()
    loaded = true
end

-- Extract hostname from URL
local function extract_host(url)
    if not url or url == "" then return nil end
    local host = url:match("^https?://([^/:]+)")
    return host and host:lower()
end

-- Check if host is in allowed list
local function is_host_allowed(host)
    if not host then return false end

    -- Direct match
    if allowed_origins[host] then
        return true
    end

    -- Subdomain match
    for allowed, _ in pairs(allowed_origins) do
        if host:match("%." .. allowed:gsub("%.", "%%.") .. "$") then
            return true
        end
    end

    return false
end

-- Get the origin to use for CORS (returns nil if not allowed)
function _M.get_allowed_origin()
    load_origins()

    -- Allow all if wildcard is set
    if allowed_origins["*"] then
        return "*"
    end

    local origin = ngx.var.http_origin or ""
    local referer = ngx.var.http_referer or ""

    local origin_host = extract_host(origin)
    local referer_host = extract_host(referer)

    -- Check origin first
    if origin_host and is_host_allowed(origin_host) then
        return origin  -- Return full origin for CORS
    end

    -- Check referer
    if referer_host and is_host_allowed(referer_host) then
        -- Build origin from referer
        local protocol = referer:match("^(https?)://")
        if protocol then
            return protocol .. "://" .. referer_host
        end
    end

    return nil
end

-- Check if origin is allowed
function _M.check()
    return _M.get_allowed_origin() ~= nil
end

-- Set CORS headers
function _M.set_cors_headers()
    local origin = _M.get_allowed_origin()
    if origin then
        ngx.header["Access-Control-Allow-Origin"] = origin
        ngx.header["Access-Control-Allow-Methods"] = "GET, OPTIONS"
        ngx.header["Access-Control-Allow-Headers"] = "Origin, Content-Type, Accept, Range"
        ngx.header["Access-Control-Expose-Headers"] = "Content-Length, Content-Range"
        ngx.header["Access-Control-Allow-Credentials"] = "true"
    end
end

-- Handle OPTIONS preflight
function _M.handle_options()
    local origin = _M.get_allowed_origin()
    if origin then
        ngx.header["Access-Control-Allow-Origin"] = origin
        ngx.header["Access-Control-Allow-Methods"] = "GET, OPTIONS"
        ngx.header["Access-Control-Allow-Headers"] = "Origin, Content-Type, Accept, Range"
        ngx.header["Access-Control-Max-Age"] = "86400"
        ngx.header["Access-Control-Allow-Credentials"] = "true"
        ngx.status = 204
        return ngx.exit(204)
    else
        ngx.status = 403
        return ngx.exit(403)
    end
end

-- Deny access with 403
function _M.deny()
    ngx.status = 403
    ngx.header["Content-Type"] = "application/json"
    ngx.say('{"error": "Forbidden: Origin not allowed"}')
    return ngx.exit(403)
end

return _M
