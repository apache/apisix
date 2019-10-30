local core = require("apisix.core")
local tab_insert = table.insert
local tab_concat = table.concat
local re_gmatch = ngx.re.gmatch
local ipairs = ipairs

local lrucache = core.lrucache.new({
    ttl = 300, count = 100
})


local schema = {
    type = "object",
    properties = {
        ret_code = {type = "integer", minimum = 200, default = 302},
        uri = {type = "string", minLength = 2},
    },
    required = {"uri"},
}


local plugin_name = "rewrite"

local _M = {
    version = 0.1,
    priority = 900,
    name = plugin_name,
    schema = schema,
}


local function parse_uri(uri)

    local reg = [[ (\\\$[0-9a-zA-Z_]+) | ]]         -- \$host
                .. [[ \$\{([0-9a-zA-Z_]+)\} | ]]    -- ${host}
                .. [[ \$([0-9a-zA-Z_]+) | ]]        -- $host
                .. [[ (\$|[^$\\]+) ]]               -- $ or others
    local iterator, err = re_gmatch(uri, reg, "jiox")
    if not iterator then
        return nil, err
    end

    local t = {}
    while true do
        local m, err = iterator()
        if err then
            return nil, err
        end

        if not m then
            break
        end

        tab_insert(t, m)
    end

    return t
end


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    local uri_segs, err = parse_uri(conf.uri)
    if not uri_segs then
        return false, err
    end
    core.log.info(core.json.delay_encode(uri_segs))

    return true
end


    local tmp = {}
local function concat_new_uri(uri, ctx)
    local pased_uri_segs, err = lrucache(uri, nil, parse_uri, uri)
    if not pased_uri_segs then
        return nil, err
    end

    core.table.clear(tmp)

    for _, uri_segs in ipairs(pased_uri_segs) do
        local pat1 = uri_segs[1]    -- \$host
        local pat2 = uri_segs[2]    -- ${host}
        local pat3 = uri_segs[3]    -- $host
        local pat4 = uri_segs[4]    -- $ or others
        core.log.info("parsed uri segs: ", core.json.delay_encode(uri_segs))

        if pat2 or pat3 then
            tab_insert(tmp, ctx.var[pat2 or pat3])
        else
            tab_insert(tmp, pat1 or pat4)
        end
    end

    return tab_concat(tmp, "")
end


function _M.rewrite(conf, ctx)
    core.log.info("plugin rewrite phase, conf: ", core.json.delay_encode(conf))

    local new_uri, err = concat_new_uri(conf.uri, ctx)
    if not new_uri then
        core.log.error("failed to generate new uri by: ", conf.uri, " error: ",
                       err)
        core.response.exit(500)
    end

    core.response.set_header("Location", new_uri)
    core.response.exit(conf.ret_code)
end


return _M
