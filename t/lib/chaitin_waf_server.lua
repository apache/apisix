local _M = {}

local function get_socket()
    ngx.flush(true)
    local sock, err = ngx.req.socket(true)
    if not sock then
        core.log.error("failed to get the request socket: ", err)
        return nil
    end
    return sock
end

function _M.pass()
    local sock = get_socket()
    sock:send({ string.char(65), string.char(1), string.char(0), string.char(0), string.char(0) })
    sock:send(".")
    sock:send({ string.char(165), string.char(77), string.char(0), string.char(0), string.char(0) })
    sock:send("{\"event_id\":\"1e902e84bf5a4ead8f7760a0fe2c7719\",\"request_hit_whitelist\":false}")

    ngx.exit(200)
end

-- 返回值会被分为如下的形式

-- 长度为 5 bytes 的 packet
-- 紧跟一段 body

-- 其中：
-- 第一个 packet 的 第一个 byte 需要 & 0x40 == 0x40
-- 最后一个 packet 的 第一个 byte 需要 & 0x80 == 0x80

-- tag 为 packet 的第一个 byte & !0x40 & !0x80

function _M.reject()
    local sock = get_socket()
    sock:send({ string.char(65), string.char(1), string.char(0), string.char(0), string.char(0) })
    sock:send("?")
    sock:send({ string.char(2), string.char(3), string.char(0), string.char(0), string.char(0) })
    sock:send("403")
    sock:send({ string.char(37), string.char(77), string.char(0), string.char(0), string.char(0) })
    sock:send("{\"event_id\":\"b3c6ce574dc24f09a01f634a39dca83b\",\"request_hit_whitelist\":false}")
    sock:send({ string.char(35), string.char(79), string.char(0), string.char(0), string.char(0) })
    sock:send("Set-Cookie:sl-session=ulgbPfMSuWRNsi/u7Aj9aA==; Domain=; Path=/; Max-Age=86400\n")
    sock:send({ string.char(164), string.char(51), string.char(0), string.char(0), string.char(0) })
    sock:send("<!-- event_id: b3c6ce574dc24f09a01f634a39dca83b -->")

    ngx.exit(200)
end

function _M.timeout()
    ngx.sleep(70)
    _M.pass()
end

return _M
