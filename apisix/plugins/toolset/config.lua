return {
    trace = {
        rate = 1, -- allow only 1 request per 100 requests
        hosts = {}, -- only the requests carrying these host headers will be traced
        paths = {}, -- only these request_uris will be traced
        gen_uid = false, -- adds a UID to the trace if none of the traceable headers are found
        vars = {}, -- add these nginx or inbuilt variables to trace table
        timespan_threshold = 0 -- requests taking longer than this value (in seconds) will be traced
    },
    table_count = {
        lua_modules = {}, -- change it
        interval = 5,
        depth = 10, -- when it is not passed, default depth will be 1
        -- optional, default is all APISIX processes
        scopes = {"worker", "privileged agent"}
    }
}
