local ngx_re = require("ngx.re")
local open = io.open


local _M = {version = 0.1}


function _M.get_seed_from_urandom()
    local frandom, err = open("/dev/urandom", "rb")
    if not frandom then
        return nil, 'failed to open /dev/urandom: ' .. err
    end

    local str = frandom:read(4)
    frandom:close()
    if not str then
        return nil, 'failed to read data from /dev/urandom'
    end

    local seed = 0
    for i = 1, 4 do
        seed = 256 * seed + str:byte(i)
    end
    return seed
end


function _M.split_uri(uri)
    return ngx_re.split(uri, "/")
end


return _M
