local _M = {}

local ffi = require "ffi"
local C = ffi.C

ffi.cdef[[
    int mkdir(const char *pathname, int mode);
]]

local CACHE_DIR = "/cache"
local cache_enabled = true

-- Simple hash function for cache keys
local function hash_key(str)
    local h = 5381
    for i = 1, #str do
        h = ((h * 33) + string.byte(str, i)) % 0xFFFFFFFF
    end
    return string.format("%08x", h)
end

-- Get cache expiry in seconds from env
local function get_expiry_seconds()
    local expiry = os.getenv("CACHE_EXPIRY") or "2d"
    local num, unit = expiry:match("^(%d+)(%a)$")
    if not num then return 172800 end -- default 2 days

    num = tonumber(num)
    if unit == "d" then return num * 86400
    elseif unit == "h" then return num * 3600
    elseif unit == "m" then return num * 60
    else return num end
end

-- Check if caching is enabled
local function is_enabled()
    local size = os.getenv("CACHE_SIZE") or "10g"
    return size ~= "0"
end

-- Ensure cache directory exists
local function ensure_dir(path)
    local dir = path:match("(.*/)")
    if dir then
        os.execute("mkdir -p " .. dir)
    end
end

-- Get cache file path for URL
function _M.get_path(url)
    local key = hash_key(url)
    local subdir = key:sub(1, 2)
    return string.format("%s/%s/%s", CACHE_DIR, subdir, key)
end

-- Check if cached and not expired
function _M.get(url)
    if not is_enabled() then return nil end

    local path = _M.get_path(url)
    local file = io.open(path, "rb")
    if not file then return nil end

    -- Check expiry
    local attr = io.popen("stat -c %Y " .. path .. " 2>/dev/null"):read("*a")
    local mtime = tonumber(attr)
    if mtime then
        local age = os.time() - mtime
        if age > get_expiry_seconds() then
            file:close()
            os.remove(path)
            return nil
        end
    end

    -- Read metadata (first line: content-type)
    local content_type = file:read("*l")
    local body = file:read("*a")
    file:close()

    return {
        content_type = content_type,
        body = body
    }
end

-- Store in cache
function _M.set(url, content_type, body)
    if not is_enabled() then return end
    if not body or #body == 0 then return end

    local path = _M.get_path(url)
    ensure_dir(path)

    local file = io.open(path, "wb")
    if not file then
        ngx.log(ngx.WARN, "Failed to write cache: ", path)
        return
    end

    -- Write metadata + body
    file:write(content_type or "application/octet-stream")
    file:write("\n")
    file:write(body)
    file:close()
end

-- Get cache status for headers
function _M.status(url)
    if not is_enabled() then return "DISABLED" end
    local path = _M.get_path(url)
    local file = io.open(path, "rb")
    if file then
        file:close()
        return "HIT"
    end
    return "MISS"
end

return _M
