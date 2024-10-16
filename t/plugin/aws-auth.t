#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

use t::APISIX 'no_plan';

repeat_each(2);
no_long_string();
no_root_location();

run_tests;

__DATA__

=== TEST 1: Utils Test: hmac256_bin
--- config
location /t {
    content_by_lua_block {
        local utils        = require("apisix.plugins.aws-auth.utils")
        local hex_encode   = require("resty.string").to_hex

        local body = hex_encode(utils.hmac256_bin("foo", "bar"))
        ngx.say(body)
    }
}
--- request
GET /t
--- response_body
f9320baf0249169e73850cd6156ded0106e2bb6ad8cab01b7bbbebe6d1065317



=== TEST 2: Utils Test: sha256
--- config
location /t {
    content_by_lua_block {
        local utils = require("apisix.plugins.aws-auth.utils")

        local body = utils.sha256("Welcome to Amazon S3.")
        ngx.say(body)
    }
}
--- request
GET /t
--- response_body
44ce7dd67c959e0d3524ffac1771dfbba87d2b6b4b4e99e42034a8b803f8b072



=== TEST 3: Utils Test: iso8601_to_timestamp
--- config
location /t {
    content_by_lua_block {
        local utils = require("apisix.plugins.aws-auth.utils")

        local body = utils.iso8601_to_timestamp("20160801T223241Z")
        ngx.say(body)
    }
}
--- request
GET /t
--- response_body
1470090761



=== TEST 4: Utils Test: aws_uri_encode: reserved characters
--- config
location /t {
    content_by_lua_block {
        local utils = require("apisix.plugins.aws-auth.utils")

        local body = utils.aws_uri_encode([[AZaz09-._~]], false)
        ngx.say(body)
    }
}
--- request
GET /t
--- response_body
AZaz09-._~



=== TEST 5: Utils Test: aws_uri_encode: space is reserved characters
--- config
location /t {
    content_by_lua_block {
        local utils = require("apisix.plugins.aws-auth.utils")

        local body = utils.aws_uri_encode(" ", false)
        ngx.say(body)
    }
}
--- request
GET /t
--- response_body
%20



=== TEST 6: Utils Test: aws_uri_encode: expect reserved characters
--- config
location /t {
    content_by_lua_block {
        local utils = require("apisix.plugins.aws-auth.utils")

        local body = utils.aws_uri_encode([[`!@#$%^&*()+=[]\{}|;':",/<>?]] .. "\r" .. "\n", false)
        ngx.say(body)
    }
}
--- request
GET /t
--- response_body
%60%21%40%23%24%25%5E%26%2A%28%29%2B%3D%5B%5D%5C%7B%7D%7C%3B%27%3A%22%2C%2F%3C%3E%3F%0D%0A



=== TEST 7: Utils Test: aws_uri_encode: encode path
--- config
location /t {
    content_by_lua_block {
        local utils = require("apisix.plugins.aws-auth.utils")

        local body = utils.aws_uri_encode("/amzn-s3-demo-bucket/myphoto.jpg", true)
        ngx.say(body)
    }
}
--- request
GET /t
--- response_body
/amzn-s3-demo-bucket/myphoto.jpg



=== TEST 8: Utils Test: build_canonical_uri: mixed (un)reserved characters
--- config
location /t {
    content_by_lua_block {
        local utils = require("apisix.plugins.aws-auth.utils")

        local body = utils.build_canonical_uri("test$file.text")
        ngx.say(body)
    }
}
--- request
GET /t
--- response_body
/test%24file.text



=== TEST 9: Utils Test: build_canonical_uri: empty uri string
--- config
location /t {
    content_by_lua_block {
        local utils = require("apisix.plugins.aws-auth.utils")

        local body = utils.build_canonical_uri("")
        ngx.say(body)
    }
}
--- request
GET /t
--- response_body
/



=== TEST 10: Utils Test: build_canonical_uri: test slash
--- config
location /t {
    content_by_lua_block {
        local utils = require("apisix.plugins.aws-auth.utils")

        local body = utils.build_canonical_uri("hello/")
        ngx.say(body)
    }
}
--- request
GET /t
--- response_body
/hello



=== TEST 11: Utils Test: build_canonical_query_string
--- config
location /t {
    content_by_lua_block {
        local utils = require("apisix.plugins.aws-auth.utils")

        local query_string = {}
        query_string["prefix"]   = "somePrefix"
        query_string["marker"]   = "someMarker"
        query_string["max-keys"] = "20"

        local body = utils.build_canonical_query_string(query_string)
        ngx.say(body)
    }
}
--- request
GET /t
--- response_body
marker=someMarker&max-keys=20&prefix=somePrefix



=== TEST 12: Utils Test: build_canonical_query_string: with empty string value
--- config
location /t {
    content_by_lua_block {
        local utils = require("apisix.plugins.aws-auth.utils")

        local query_string = {}
        query_string["acl"] = ""

        local body = utils.build_canonical_query_string(query_string)
        ngx.say(body)
    }
}
--- request
GET /t
--- response_body
acl=



=== TEST 13: Utils Test: build_canonical_query_string: with UriEncode
--- config
location /t {
    content_by_lua_block {
        local utils = require("apisix.plugins.aws-auth.utils")

        local query_string = {}
        query_string["AZaz09-._~"] = " %/="

        local body = utils.build_canonical_query_string(query_string)
        ngx.say(body)
    }
}
--- request
GET /t
--- response_body
AZaz09-._~=%20%25%2F%3D



=== TEST 14: Utils Test: build_canonical_headers: return canonical_headers
--- config
location /t {
    content_by_lua_block {
        local utils = require("apisix.plugins.aws-auth.utils")

        local headers = {}
        headers["Host"] = "examplebucket.s3.amazonaws.com"
        headers["Date"] = "Fri, 24 May 2013 00:00:00 GMT"
        headers["x-amz-date"] = "20130524T000000Z"
        headers["x-amz-storage-class"] = "REDUCED_REDUNDANCY"
        headers["x-amz-content-sha256"] = "44ce7dd67c959e0d3524ffac1771dfbba87d2b6b4b4e99e42034a8b803f8b072"

        local r1, r2 = utils.build_canonical_headers(headers)
        ngx.say(r1)
    }
}
--- request
GET /t
--- response_body eval
"date:Fri, 24 May 2013 00:00:00 GMT
host:examplebucket.s3.amazonaws.com
x-amz-content-sha256:44ce7dd67c959e0d3524ffac1771dfbba87d2b6b4b4e99e42034a8b803f8b072
x-amz-date:20130524T000000Z
x-amz-storage-class:REDUCED_REDUNDANCY

"



=== TEST 15: Utils Test: build_canonical_headers: return signed_headers
--- config
location /t {
    content_by_lua_block {
        local utils = require("apisix.plugins.aws-auth.utils")

        local headers = {}
        headers["Host"] = "examplebucket.s3.amazonaws.com"
        headers["Date"] = "Fri, 24 May 2013 00:00:00 GMT"
        headers["x-amz-date"] = "20130524T000000Z"
        headers["x-amz-storage-class"] = "REDUCED_REDUNDANCY"
        headers["x-amz-content-sha256"] = "44ce7dd67c959e0d3524ffac1771dfbba87d2b6b4b4e99e42034a8b803f8b072"

        local r1, r2 = utils.build_canonical_headers(headers)
        ngx.say(r2)
    }
}
--- request
GET /t
--- response_body
date;host;x-amz-content-sha256;x-amz-date;x-amz-storage-class



=== TEST 16: Utils Test: create_signing_key
--- config
location /t {
    content_by_lua_block {
        local utils = require("apisix.plugins.aws-auth.utils")
        local hex_encode   = require("resty.string").to_hex

        local headers = {}
        headers["Host"] = "examplebucket.s3.amazonaws.com"
        headers["Date"] = "Fri, 24 May 2013 00:00:00 GMT"
        headers["x-amz-date"] = "20130524T000000Z"
        headers["x-amz-storage-class"] = "REDUCED_REDUNDANCY"
        headers["x-amz-content-sha256"] = "44ce7dd67c959e0d3524ffac1771dfbba87d2b6b4b4e99e42034a8b803f8b072"

        local body = utils.create_signing_key(
            "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
            "20130524",
            "us-east-1",
            "s3"
        )
        body = hex_encode(body)
        ngx.say(body)
    }
}
--- request
GET /t
--- response_body
dbb893acc010964918f1fd433add87c70e8b0db6be30c1fbeafefa5ec6ba8378



=== TEST 17: Utils Test: generate_signature: GET Object
--- config
location /t {
    content_by_lua_block {
        local utils = require("apisix.plugins.aws-auth.utils")
        local hex_encode   = require("resty.string").to_hex

        local headers = {}
        headers["Host"] = "examplebucket.s3.amazonaws.com"
        headers["Range"] = "bytes=0-9"
        headers["x-amz-content-sha256"] = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        headers["x-amz-date"] = "20130524T000000Z"

        local body = utils.generate_signature(
            "GET",
            "/test.txt",
            nil,
            headers,
            nil,
            "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
            1369353600,    -- "20130524T000000Z"
            "us-east-1",
            "s3"
        )
        ngx.say(body)
    }
}
--- request
GET /t
--- response_body
f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41



=== TEST 18: Utils Test: generate_signature: PUT Object
--- config
location /t {
    content_by_lua_block {
        local utils = require("apisix.plugins.aws-auth.utils")
        local hex_encode   = require("resty.string").to_hex

        local headers = {}
        headers["Host"] = "examplebucket.s3.amazonaws.com"
        headers["Date"] = "Fri, 24 May 2013 00:00:00 GMT"
        headers["x-amz-date"] = "20130524T000000Z"
        headers["x-amz-storage-class"] = "REDUCED_REDUNDANCY"
        headers["x-amz-content-sha256"] = "44ce7dd67c959e0d3524ffac1771dfbba87d2b6b4b4e99e42034a8b803f8b072"

        local body = utils.generate_signature(
            "PUT",
            "test$file.text",
            nil,
            headers,
            "Welcome to Amazon S3.",
            "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
            1369353600,    -- "20130524T000000Z"
            "us-east-1",
            "s3"
        )
        ngx.say(body)
    }
}
--- request
GET /t
--- response_body
98ad721746da40c64f1a55b78f14c238d841ea1380cd77a1b5971af0ece108bd



=== TEST 19: Utils Test: generate_signature: GET Bucket Lifecycle
--- config
location /t {
    content_by_lua_block {
        local utils = require("apisix.plugins.aws-auth.utils")
        local hex_encode   = require("resty.string").to_hex

        local headers = {}
        headers["Host"] = "examplebucket.s3.amazonaws.com"
        headers["x-amz-date"] = "20130524T000000Z"
        headers["x-amz-content-sha256"] = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

        local query_string = {}
        query_string["lifecycle"] = ""

        local body = utils.generate_signature(
            "GET",
            "",
            query_string,
            headers,
            "",
            "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
            1369353600,    -- "20130524T000000Z"
            "us-east-1",
            "s3"
        )
        ngx.say(body)
    }
}
--- request
GET /t
--- response_body
fea454ca298b7da1c68078a5d1bdbfbbe0d65c699e0f91ac7a200a0136783543



=== TEST 20: Utils Test: generate_signature: Get Bucket (List Objects)
--- config
location /t {
    content_by_lua_block {
        local utils = require("apisix.plugins.aws-auth.utils")
        local hex_encode   = require("resty.string").to_hex

        local headers = {}
        headers["Host"] = "examplebucket.s3.amazonaws.com"
        headers["x-amz-date"] = "20130524T000000Z"
        headers["x-amz-content-sha256"] = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

        local query_string = {}
        query_string["max-keys"] = "2"
        query_string["prefix"]   = "J"

        local body = utils.generate_signature(
            "GET",
            "",
            query_string,
            headers,
            "",
            "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
            1369353600,    -- "20130524T000000Z"
            "us-east-1",
            "s3"
        )
        ngx.say(body)
    }
}
--- request
GET /t
--- response_body
34b48302e7b5fa45bde8084f4b7868a86f0a534bc59db6670ed5711ef69dc6f7
