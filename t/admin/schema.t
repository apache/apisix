use t::APISix 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();
log_level("info");

run_tests;

__DATA__

=== TEST 1: get route schema
--- request
GET /apisix/admin/schema/route
--- response_body
{
    "type": "object",
    "properties": {
        "methods": {
            "type": "array",
            "items": {
                "description": "HTTP method",
                "type": "string",
                "enum": ["GET", "PUT", "POST", "DELETE"]
            },
            "uniqueItems": true
        },
        "plugins": {"type":"object"},
        "upstream": {"type":"object","required":["nodes","type"],"additionalProperties":false,"properties":{"type":{"type":"string","enum":["chash","roundrobin"],"description":"algorithms of load balancing"},"nodes":{"type":"object","patternProperties":{".*":{"type":"integer","minimum":1,"description":"weight of node"}},"minProperties":1,"description":"nodes of upstream"},"key":{"type":"string","enum":["remote_addr"],"description":"the key of chash for dynamic load balancing"},"id":{"anyOf":[{"type":"string","pattern":"^[0-9]+$","maxLength":32,"minLength":1},{"type":"integer","minimum":1}]}}},
        "uri": {
            "type": "string"
        },
        "host": {
            "type": "string",
            "pattern": "^\\*?[0-9a-zA-Z-.]+$"
        },
        "remote_addr": {
            "description": "client IP",
            "type": "string",
            "anyOf": [
              {"pattern": "^[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}$"},
              {"pattern": "^[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}/[0-9]{1,2}$"}
            ]
        },
        "service_id": {"anyOf":[{"type":"string","pattern":"^[0-9]+$","maxLength":32,"minLength":1},{"type":"integer","minimum":1}]},
        "upstream_id": {"anyOf":[{"type":"string","pattern":"^[0-9]+$","maxLength":32,"minLength":1},{"type":"integer","minimum":1}]},
        "id": {"anyOf":[{"type":"string","pattern":"^[0-9]+$","maxLength":32,"minLength":1},{"type":"integer","minimum":1}]}    },
    "anyOf": [
        {"required": ["plugins", "uri"]},
        {"required": ["upstream", "uri"]},
        {"required": ["upstream_id", "uri"]},
        {"required": ["service_id", "uri"]}
    ],
    "additionalProperties": false
}
--- no_error_log
[error]



=== TEST 2: get service schema
--- request
GET /apisix/admin/schema/service
--- response_body
{"type":"object","additionalProperties":false,"anyOf":[{"required":["upstream"]},{"required":["upstream_id"]},{"required":["plugins"]}],"properties":{"upstream_id":{"anyOf":[{"type":"string","pattern":"^[0-9]+$","maxLength":32,"minLength":1},{"type":"integer","minimum":1}]},"upstream":{"type":"object","required":["nodes","type"],"additionalProperties":false,"properties":{"type":{"type":"string","enum":["chash","roundrobin"],"description":"algorithms of load balancing"},"nodes":{"type":"object","patternProperties":{".*":{"type":"integer","minimum":1,"description":"weight of node"}},"minProperties":1,"description":"nodes of upstream"},"key":{"type":"string","enum":["remote_addr"],"description":"the key of chash for dynamic load balancing"},"id":{"anyOf":[{"type":"string","pattern":"^[0-9]+$","maxLength":32,"minLength":1},{"type":"integer","minimum":1}]}}},"id":{"anyOf":[{"type":"string","pattern":"^[0-9]+$","maxLength":32,"minLength":1},{"type":"integer","minimum":1}]},"plugins":{"type":"object"}}}
--- no_error_log
[error]



=== TEST 3: get not exist schema
--- request
GET /apisix/admin/schema/noexits
--- error_code: 404
--- no_error_log
[error]



=== TEST 4: wrong method
--- request
PUT /apisix/admin/schema/service
--- error_code: 404
--- no_error_log
[error]



=== TEST 5: wrong method
--- request
POST /apisix/admin/schema/service
--- error_code: 404
--- no_error_log
[error]
