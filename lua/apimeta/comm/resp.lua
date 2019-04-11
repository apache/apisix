-- Copyright (C) Yuansheng Wang

local ngx = ngx
local ngx_say = ngx.say
local ngx_exit = ngx.exit

return function (code, body)
    if not body then
        ngx_exit(code)
        return
    end

    ngx.status = code
    ngx_say(body)
    ngx_exit(code)
end
