use t::APISix 'no_plan';

repeat_each(2);
log_level('info');
no_root_location();

run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local rapidjson = require('rapidjson')

            local args_schema = {
                type = "object",
                properties = {
                    i = {type = "number", minimum = 0},
                    s = {type = "string", format = "uri"},
                    t = {type = "array", minItems = 1},
                }
}

            local sd = rapidjson.SchemaDocument(args_schema)
            local validator = rapidjson.SchemaValidator(sd)

            local d = rapidjson.Document({i = 1, s = "s", t = {1}})

            local ok, message = validator:validate(d)
            ngx.say(ok)
            ngx.say(message)
        }
    }
--- request
GET /t
--- response_body
true
