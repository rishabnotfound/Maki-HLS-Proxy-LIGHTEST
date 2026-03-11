local _M = {}

local CACHE_DIR = "/cache"
local SIZE_CHECK_INTERVAL = 30  -- Check size every 30 seconds
local last_size_check = 0

-- Simple hash function for cache keys
local function hash_key(str)
    local h = 5381
    for i = 1, #str do
        h = ((h * 33) + string.byte(str, i)) % 0xFFFFFFFF
    end
    return string.format("%08x", h)
end

-- Parse size string (e.g., "5g" -> bytes)
local function parse_size(size_str)
    if not size_str or size_str == "0" then return 0 end
    local num, unit = size_str:match("^(%d+)(%a?)$")
    if not num then return 10 * 1024 * 1024 * 1024 end -- default 10GB

    num = tonumber(num)
    unit = unit:lower()
    if unit == "g" then return num * 1024 * 1024 * 1024
    elseif unit == "m" then return num * 1024 * 1024
    elseif unit == "k" then return num * 1024
    else return num end
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

-- Get max cache size in bytes
local function get_max_size()
    local size = os.getenv("CACHE_SIZE") or "10g"
    return parse_size(size)
end

-- Ensure cache directory exists
local function ensure_dir(path)
    local dir = path:match("(.*/)")
    if dir then
        os.execute("mkdir -p " .. dir .. " 2>/dev/null")
    end
end

-- Get cache file path for URL
function _M.get_path(url)
    local key = hash_key(url)
    local subdir = key:sub(1, 2)
    return string.format("%s/%s/%s", CACHE_DIR, subdir, key)
end

-- Get current cache size in KB (Alpine compatible)
local function get_cache_size_kb()
    local handle = io.popen("du -sk " .. CACHE_DIR .. " 2>/dev/null | cut -f1")
    if not handle then return 0 end
    local result = handle:read("*a")
    handle:close()
    return tonumber(result) or 0
end

-- Clean expired files and enforce size limit (Alpine/BusyBox compatible)
local function cleanup_cache()
    local now = os.time()

    -- Don't check too often
    if now - last_size_check < SIZE_CHECK_INTERVAL then
        return
    end
    last_size_check = now

    local expiry = get_expiry_seconds()
    local max_size_kb = math.floor(get_max_size() / 1024)  -- Convert to KB
    local current_size_kb = get_cache_size_kb()

    ngx.log(ngx.DEBUG, "Cache check: ", current_size_kb, "KB / ", max_size_kb, "KB limit")

    -- First pass: delete expired files (BusyBox find supports -mmin and -delete)
    local expiry_mins = math.floor(expiry / 60)
    if expiry_mins > 0 then
        os.execute(string.format(
            "find %s -type f -mmin +%d -delete 2>/dev/null",
            CACHE_DIR, expiry_mins
        ))
    end

    -- Recheck size after expiry cleanup
    current_size_kb = get_cache_size_kb()

    -- Second pass: if still over limit, delete oldest files until under 80% of limit
    if current_size_kb > max_size_kb then
        ngx.log(ngx.NOTICE, "Cache over limit: ", current_size_kb, "KB > ", max_size_kb, "KB, cleaning...")

        local target_kb = math.floor(max_size_kb * 0.8)  -- Target 80% of max

        -- Get all cache files sorted by modification time (oldest first)
        -- Using ls -ltrR and parsing, Alpine/BusyBox compatible
        local handle = io.popen(string.format(
            "find %s -type f -exec ls -l {} \\; 2>/dev/null | sort -k6,7 | awk '{print $NF}'",
            CACHE_DIR
        ))

        if handle then
            local files = {}
            for line in handle:lines() do
                if line and #line > 0 then
                    table.insert(files, line)
                end
            end
            handle:close()

            -- Delete oldest files until we're under target
            local deleted = 0
            for _, filepath in ipairs(files) do
                if current_size_kb <= target_kb then
                    break
                end

                -- Get file size before deleting
                local size_handle = io.popen("ls -sk " .. filepath .. " 2>/dev/null | cut -d' ' -f1")
                local file_size_kb = 0
                if size_handle then
                    file_size_kb = tonumber(size_handle:read("*a")) or 0
                    size_handle:close()
                end

                os.remove(filepath)
                current_size_kb = current_size_kb - file_size_kb
                deleted = deleted + 1
            end

            ngx.log(ngx.NOTICE, "Cache cleanup: deleted ", deleted, " files, now ", current_size_kb, "KB")
        end
    end

    -- Clean empty directories
    os.execute("find " .. CACHE_DIR .. " -type d -empty -delete 2>/dev/null")
end

-- Check if cached and not expired
function _M.get(url)
    if not is_enabled() then return nil end

    local path = _M.get_path(url)
    local file = io.open(path, "rb")
    if not file then return nil end

    -- Check expiry (stat -c works on Alpine)
    local handle = io.popen("stat -c %Y " .. path .. " 2>/dev/null")
    local attr = handle and handle:read("*a") or ""
    if handle then handle:close() end

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

    -- Run cleanup check before writing
    cleanup_cache()

    -- Check if we have space (quick check)
    local current_size_kb = get_cache_size_kb()
    local max_size_kb = math.floor(get_max_size() / 1024)
    local body_size_kb = math.ceil(#body / 1024)

    if current_size_kb + body_size_kb > max_size_kb then
        -- Force immediate cleanup
        last_size_check = 0
        cleanup_cache()

        -- Recheck - if still over, skip caching this file
        current_size_kb = get_cache_size_kb()
        if current_size_kb + body_size_kb > max_size_kb then
            ngx.log(ngx.WARN, "Cache full, skipping: ", #body, " bytes")
            return
        end
    end

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
