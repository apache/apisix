local log = require("apisix.core.log")
local uuid = require('resty.jit-uuid')
local smatch = string.match
local open = io.open


local prefix = ngx.config.prefix()
local apisix_uid

local _M = {version = 0.1}


local function rtrim(str)
    return smatch(str, "^(.-)%s*$")
end


local function read_file(path)
    local file = open(path, "rb") -- r read mode and b binary mode
    if not file then
        return nil
    end

    local content = file:read("*a")  -- *a or *all reads the whole file
    file:close()
    return rtrim(content)
end


local function write_file(path, data)
    local file = open(path ,"w+")
    if not file then
        return nil, "failed to open file[" .. path .. "] for writing"
    end

    file:write(data)
    file:close()
    return true
end


function _M.init()
    local uid_file_path = prefix .. "/conf/apisix.uid"
    apisix_uid = read_file(uid_file_path)
    if apisix_uid then
        return
    end

    apisix_uid = uuid.generate_v4()
    log.notice("not found apisix uid, generate a new one: ", apisix_uid)

    local ok, err = write_file(uid_file_path, apisix_uid)
    if not ok then
        log.error(err)
    end
end


function _M.get()
    return apisix_uid
end


return _M
