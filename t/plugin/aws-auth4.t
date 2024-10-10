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

repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    my $user_yaml_config = <<_EOC_;
apisix:
  data_encryption:
    enable_encrypt_fields: false
_EOC_
    $block->set_value("yaml_config", $user_yaml_config);
});

run_tests;

__DATA__

=== TEST 1: Verify by Query String: add consumer with plugin aws-auth
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "aws-auth": {
                            "access_key": "AKIAIOSFODNN7EXAMPLE",
                            "secret_key": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
                        }
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 2: Verify by Query String: add aws auth plugin using admin api
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "aws-auth": {
                            "region": "us-east-1",
                            "service": "s3"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 3: Verify by Query String: missing Authentication Query String
--- request
GET /hello?
--- more_headers
Host: examplebucket.s3.amazonaws.com
Range: bytes=0-9
--- error_code: 403
--- response_body
{"message":"Missing Authentication Token"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: Missing Authentication Token



=== TEST 4: Verify by Query String: Credential: algorithm mistake
--- request
GET /hello?X-Amz-Algorithm=FAKE-ALGO&X-Amz-Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request&X-Amz-Date=20130524T000000Z&X-Amz-Expires=86400&X-Amz-SignedHeaders=host;range;x-amz-content-sha256&X-Amz-Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41
--- more_headers
Host: examplebucket.s3.amazonaws.com
Range: bytes=0-9
x-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
--- error_code: 403
--- response_body
{"message":"algorithm 'FAKE-ALGO' is not supported"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: algorithm 'FAKE-ALGO' is not supported



=== TEST 5: Verify by Query String: Credential: access key missing
--- request
GET /hello?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=/20130524/us-east-1/s3/aws4_request&X-Amz-Date=20130524T000000Z&X-Amz-Expires=86400&X-Amz-SignedHeaders=host;range;x-amz-content-sha256&X-Amz-Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41
--- more_headers
Host: examplebucket.s3.amazonaws.com
Range: bytes=0-9
x-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
--- error_code: 403
--- response_body
{"message":"access key missing"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: access key missing



=== TEST 6: Verify by Query String: Credential: date missing
--- request
GET /hello?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAIOSFODNN7EXAMPLE//us-east-1/s3/aws4_request&X-Amz-Date=20130524T000000Z&X-Amz-Expires=86400&X-Amz-SignedHeaders=host;range;x-amz-content-sha256&X-Amz-Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41
--- more_headers
Host: examplebucket.s3.amazonaws.com
Range: bytes=0-9
x-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
--- error_code: 403
--- response_body
{"message":"date missing"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: date missing



=== TEST 7: Verify by Query String: Credential: region missing
--- request
GET /hello?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAIOSFODNN7EXAMPLE/20130524//s3/aws4_request&X-Amz-Date=20130524T000000Z&X-Amz-Expires=86400&X-Amz-SignedHeaders=host;range;x-amz-content-sha256&X-Amz-Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41
--- more_headers
Host: examplebucket.s3.amazonaws.com
Range: bytes=0-9
x-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
--- error_code: 403
--- response_body
{"message":"region missing"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: region missing



=== TEST 8: Verify by Query String: Credential: invalid region
--- request
GET /hello?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAIOSFODNN7EXAMPLE/20130524/fake-region/s3/aws4_request&X-Amz-Date=20130524T000000Z&X-Amz-Expires=86400&X-Amz-SignedHeaders=host;range;x-amz-content-sha256&X-Amz-Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41
--- more_headers
Host: examplebucket.s3.amazonaws.com
Range: bytes=0-9
x-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
--- error_code: 403
--- response_body
{"message":"Credential should be scoped to a valid Region, not 'fake-region'"}
--- grep_error_log eval
qr/client request can't be validated: Credential should be scoped to a valid Region, not [^,]+/
--- grep_error_log_out
client request can't be validated: Credential should be scoped to a valid Region, not 'fake-region'



=== TEST 9: Verify by Query String: Credential: service missing
--- request
GET /hello?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1//aws4_request&X-Amz-Date=20130524T000000Z&X-Amz-Expires=86400&X-Amz-SignedHeaders=host;range;x-amz-content-sha256&X-Amz-Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41
--- more_headers
Host: examplebucket.s3.amazonaws.com
Range: bytes=0-9
x-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
--- error_code: 403
--- response_body
{"message":"service missing"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: service missing



=== TEST 10: Verify by Query String: Credential: invalid service
--- request
GET /hello?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/fake-service/aws4_request&X-Amz-Date=20130524T000000Z&X-Amz-Expires=86400&X-Amz-SignedHeaders=host;range;x-amz-content-sha256&X-Amz-Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41
--- more_headers
Host: examplebucket.s3.amazonaws.com
Range: bytes=0-9
x-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
--- error_code: 403
--- response_body
{"message":"Credential should be scoped to correct service: 'fake-service'"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: Credential should be scoped to correct service: 'fake-service'



=== TEST 11: Verify by Query String: Credential: invalid terminator
--- request
GET /hello?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/not_aws4_request&X-Amz-Date=20130524T000000Z&X-Amz-Expires=86400&X-Amz-SignedHeaders=host;range;x-amz-content-sha256&X-Amz-Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41
--- more_headers
Host: examplebucket.s3.amazonaws.com
Range: bytes=0-9
x-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
--- error_code: 403
--- response_body
{"message":"Credential should be scoped with a valid terminator: 'aws4_request'"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: Credential should be scoped with a valid terminator: 'aws4_request'



=== TEST 12: Verify by Query String: signed_header: Host missing
--- request
GET /hello?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request&X-Amz-Date=20130524T000000Z&X-Amz-Expires=86400&X-Amz-SignedHeaders=range;x-amz-content-sha256&X-Amz-Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41
--- more_headers
Host: examplebucket.s3.amazonaws.com
Range: bytes=0-9
x-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
--- error_code: 403
--- response_body
{"message":"header 'Host' is not signed"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: header 'Host' is not signed



=== TEST 13: Verify by Query String: clock_skew: Date in Credential scope is dismatch X-Amz-Date parameter
--- request
GET /hello?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request&X-Amz-Date=20000101T000000Z&X-Amz-Expires=86400&X-Amz-SignedHeaders=host;range;x-amz-content-sha256&X-Amz-Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41
--- more_headers
Host: examplebucket.s3.amazonaws.com
Range: bytes=0-9
x-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
--- error_code: 403
--- response_body
{"message":"Date in Credential scope does not match YYYYMMDD from ISO-8601 version of date from HTTP"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: Date in Credential scope does not match YYYYMMDD from ISO-8601 version of date from HTTP



=== TEST 14: Verify by Query String: clock_skew: Signature expired
--- config
location /t {
    content_by_lua_block {
        local http  = require("resty.http")
        local utils = require("apisix.plugins.aws-auth.utils")

        local now       = os.time() - 100000
        local amzdate   = os.date("!%Y%m%dT%H%M%SZ", now) -- ISO 8601 20130524T000000Z
        local datestamp = os.date("!%Y%m%d", now)         -- Date w/o time, used in credential scope

        local method     = "GET"
        local path       = "/hello"
        local body       = nil
        local access_key = "AKIAIOSFODNN7EXAMPLE"
        local secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
        local region     = "us-east-1"
        local service    = "s3"
        local credential = table.concat({access_key, datestamp, region, service, "aws4_request"}, "/")

        local headers = {}
        headers["Host"]                 = "examplebucket.s3.amazonaws.com"
        headers["x-amz-content-sha256"] = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

        local _, signed_headers = utils.build_canonical_headers(headers)

        local query_string = {}

        local signature = utils.generate_signature(
            method,
            path,
            query_string,
            headers,
            body,
            secret_key,
            now,
            region,
            service
        )

        query_string["X-Amz-Algorithm"]     = "AWS4-HMAC-SHA256"
        query_string["X-Amz-Credential"]    = credential
        query_string["X-Amz-Date"]          = amzdate
        query_string["X-Amz-Expires"]       = "86400"
        query_string["X-Amz-SignedHeaders"] = signed_headers
        query_string["X-Amz-Signature"]     = signature

        local query_string_list = {}
        for k,v in ipairs(query_string) do
            table.insert(query_string_list, k .. "=" .. v)
        end
        local query_string_str = ""
        if #query_string_list > 0 then
            query_string_str = "?" .. table.concat(query_string_list, "&")
        end

        local httpc = http.new()
        local uri = ngx.var.scheme .. "://" .. ngx.var.server_addr
        .. ":" .. ngx.var.server_port .. path
        local res, err = httpc:request_uri(uri,
            {
                method = method,
                body = body,
                keepalive = false,
                headers = headers,
                query = query_string
            }
        )

        ngx.status = res.status
        ngx.print(res.body)
    }
}
--- request
GET /t
--- error_code: 403
--- response_body eval
qr/{"message":"Signature expired: '.+' is now earlier than '.+'"}/
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out eval
qr/Signature expired: '.+' is now earlier than '.+'/



=== TEST 15: Verify by Query String: clock_skew: Signature in the future
--- config
location /t {
    content_by_lua_block {
        local http  = require("resty.http")
        local utils = require("apisix.plugins.aws-auth.utils")

        local now       = os.time() + 100000
        local amzdate   = os.date("!%Y%m%dT%H%M%SZ", now) -- ISO 8601 20130524T000000Z
        local datestamp = os.date("!%Y%m%d", now)         -- Date w/o time, used in credential scope

        local method     = "GET"
        local path       = "/hello"
        local body       = nil
        local access_key = "AKIAIOSFODNN7EXAMPLE"
        local secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
        local region     = "us-east-1"
        local service    = "s3"
        local credential = table.concat({access_key, datestamp, region, service, "aws4_request"}, "/")

        local headers = {}
        headers["Host"]                 = "examplebucket.s3.amazonaws.com"
        headers["x-amz-content-sha256"] = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

        local _, signed_headers = utils.build_canonical_headers(headers)

        local query_string = {}

        local signature = utils.generate_signature(
            method,
            path,
            query_string,
            headers,
            body,
            secret_key,
            now,
            region,
            service
        )

        query_string["X-Amz-Algorithm"]     = "AWS4-HMAC-SHA256"
        query_string["X-Amz-Credential"]    = credential
        query_string["X-Amz-Date"]          = amzdate
        query_string["X-Amz-Expires"]       = "86400"
        query_string["X-Amz-SignedHeaders"] = signed_headers
        query_string["X-Amz-Signature"]     = signature

        local query_string_list = {}
        for k,v in ipairs(query_string) do
            table.insert(query_string_list, k .. "=" .. v)
        end
        local query_string_str = ""
        if #query_string_list > 0 then
            query_string_str = "?" .. table.concat(query_string_list, "&")
        end

        local httpc = http.new()
        local uri = ngx.var.scheme .. "://" .. ngx.var.server_addr
        .. ":" .. ngx.var.server_port .. path
        local res, err = httpc:request_uri(uri,
            {
                method = method,
                body = body,
                keepalive = false,
                headers = headers,
                query = query_string
            }
        )

        ngx.status = res.status
        ngx.print(res.body)
    }
}
--- request
GET /t
--- error_code: 403
--- response_body eval
qr/{"message":"Signature not yet current: '.+' is still later than '.+'"}/
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out eval
qr/Signature not yet current: '.+' is still later than '.+'/



=== TEST 16: Verify by Query String: Success
--- config
location /t {
    content_by_lua_block {
        local http  = require("resty.http")
        local utils = require("apisix.plugins.aws-auth.utils")

        local now       = os.time()
        local amzdate   = os.date("!%Y%m%dT%H%M%SZ", now) -- ISO 8601 20130524T000000Z
        local datestamp = os.date("!%Y%m%d", now)         -- Date w/o time, used in credential scope

        local method     = "GET"
        local path       = "/hello"
        local body       = nil
        local access_key = "AKIAIOSFODNN7EXAMPLE"
        local secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
        local region     = "us-east-1"
        local service    = "s3"
        local credential = table.concat({access_key, datestamp, region, service, "aws4_request"}, "/")

        local headers = {}
        headers["Host"]                 = "examplebucket.s3.amazonaws.com"
        headers["x-amz-content-sha256"] = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

        local _, signed_headers = utils.build_canonical_headers(headers)

        local query_string = {}

        local signature = utils.generate_signature(
            method,
            path,
            query_string,
            headers,
            body,
            secret_key,
            now,
            region,
            service
        )

        query_string["X-Amz-Algorithm"]     = "AWS4-HMAC-SHA256"
        query_string["X-Amz-Credential"]    = credential
        query_string["X-Amz-Date"]          = amzdate
        query_string["X-Amz-Expires"]       = "86400"
        query_string["X-Amz-SignedHeaders"] = signed_headers
        query_string["X-Amz-Signature"]     = signature

        local query_string_list = {}
        for k,v in ipairs(query_string) do
            table.insert(query_string_list, k .. "=" .. v)
        end
        local query_string_str = ""
        if #query_string_list > 0 then
            query_string_str = "?" .. table.concat(query_string_list, "&")
        end

        local httpc = http.new()
        local uri = ngx.var.scheme .. "://" .. ngx.var.server_addr
        .. ":" .. ngx.var.server_port .. path
        local res, err = httpc:request_uri(uri,
            {
                method = method,
                body = body,
                keepalive = false,
                headers = headers,
                query = query_string
            }
        )

        ngx.status = res.status
        ngx.print(res.body)
    }
}
--- request
GET /t
--- response_body
hello world



=== TEST 17: Verify by Query String: Consumer not found
--- config
location /t {
    content_by_lua_block {
        local http  = require("resty.http")
        local utils = require("apisix.plugins.aws-auth.utils")

        local now       = os.time()
        local amzdate   = os.date("!%Y%m%dT%H%M%SZ", now) -- ISO 8601 20130524T000000Z
        local datestamp = os.date("!%Y%m%d", now)         -- Date w/o time, used in credential scope

        local method     = "GET"
        local path       = "/hello"
        local body       = nil
        local access_key = "FAKE_ACCESS_KEY"
        local secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
        local region     = "us-east-1"
        local service    = "s3"
        local credential = table.concat({access_key, datestamp, region, service, "aws4_request"}, "/")

        local headers = {}
        headers["Host"]                 = "examplebucket.s3.amazonaws.com"
        headers["x-amz-content-sha256"] = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

        local _, signed_headers = utils.build_canonical_headers(headers)

        local query_string = {}

        local signature = utils.generate_signature(
            method,
            path,
            query_string,
            headers,
            body,
            secret_key,
            now,
            region,
            service
        )

        query_string["X-Amz-Algorithm"]     = "AWS4-HMAC-SHA256"
        query_string["X-Amz-Credential"]    = credential
        query_string["X-Amz-Date"]          = amzdate
        query_string["X-Amz-Expires"]       = "86400"
        query_string["X-Amz-SignedHeaders"] = signed_headers
        query_string["X-Amz-Signature"]     = signature

        local query_string_list = {}
        for k,v in ipairs(query_string) do
            table.insert(query_string_list, k .. "=" .. v)
        end
        local query_string_str = ""
        if #query_string_list > 0 then
            query_string_str = "?" .. table.concat(query_string_list, "&")
        end

        local httpc = http.new()
        local uri = ngx.var.scheme .. "://" .. ngx.var.server_addr
        .. ":" .. ngx.var.server_port .. path
        local res, err = httpc:request_uri(uri,
            {
                method = method,
                body = body,
                keepalive = false,
                headers = headers,
                query = query_string
            }
        )

        ngx.status = res.status
        ngx.print(res.body)
    }
}
--- request
GET /t
--- error_code: 403
--- response_body
{"message":"The security token included in the request is invalid."}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: The security token included in the request is invalid.



=== TEST 18: Verify by Query String: Consumer not found
--- config
location /t {
    content_by_lua_block {
        local http  = require("resty.http")
        local utils = require("apisix.plugins.aws-auth.utils")

        local now       = os.time()
        local amzdate   = os.date("!%Y%m%dT%H%M%SZ", now) -- ISO 8601 20130524T000000Z
        local datestamp = os.date("!%Y%m%d", now)         -- Date w/o time, used in credential scope

        local method     = "GET"
        local path       = "/hello"
        local body       = nil
        local access_key = "AKIAIOSFODNN7EXAMPLE"
        local secret_key = "FAKE_SECRET_KEY"
        local region     = "us-east-1"
        local service    = "s3"
        local credential = table.concat({access_key, datestamp, region, service, "aws4_request"}, "/")

        local headers = {}
        headers["Host"]                 = "examplebucket.s3.amazonaws.com"
        headers["x-amz-content-sha256"] = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

        local _, signed_headers = utils.build_canonical_headers(headers)

        local query_string = {}

        local signature = utils.generate_signature(
            method,
            path,
            query_string,
            headers,
            body,
            secret_key,
            now,
            region,
            service
        )

        query_string["X-Amz-Algorithm"]     = "AWS4-HMAC-SHA256"
        query_string["X-Amz-Credential"]    = credential
        query_string["X-Amz-Date"]          = amzdate
        query_string["X-Amz-Expires"]       = "86400"
        query_string["X-Amz-SignedHeaders"] = signed_headers
        query_string["X-Amz-Signature"]     = signature

        local query_string_list = {}
        for k,v in ipairs(query_string) do
            table.insert(query_string_list, k .. "=" .. v)
        end
        local query_string_str = ""
        if #query_string_list > 0 then
            query_string_str = "?" .. table.concat(query_string_list, "&")
        end

        local httpc = http.new()
        local uri = ngx.var.scheme .. "://" .. ngx.var.server_addr
        .. ":" .. ngx.var.server_port .. path
        local res, err = httpc:request_uri(uri,
            {
                method = method,
                body = body,
                keepalive = false,
                headers = headers,
                query = query_string
            }
        )

        ngx.status = res.status
        ngx.print(res.body)
    }
}
--- request
GET /t
--- error_code: 403
--- response_body
{"message":"The request signature we calculated does not match the signature you provided."}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: The request signature we calculated does not match the signature you provided.



=== TEST 19: Verify by Query String: Exceed body limit size
--- config
location /t {
    content_by_lua_block {
        local http  = require("resty.http")
        local utils = require("apisix.plugins.aws-auth.utils")

        local now       = os.time()
        local amzdate   = os.date("!%Y%m%dT%H%M%SZ", now) -- ISO 8601 20130524T000000Z
        local datestamp = os.date("!%Y%m%d", now)         -- Date w/o time, used in credential scope

        local method     = "GET"
        local path       = "/hello"
        local body       = string.rep("A", 1024*1024)
        local access_key = "AKIAIOSFODNN7EXAMPLE"
        local secret_key = "FAKE_SECRET_KEY"
        local region     = "us-east-1"
        local service    = "s3"
        local credential = table.concat({access_key, datestamp, region, service, "aws4_request"}, "/")

        local headers = {}
        headers["Host"]                 = "examplebucket.s3.amazonaws.com"
        headers["x-amz-content-sha256"] = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

        local _, signed_headers = utils.build_canonical_headers(headers)

        local query_string = {}

        local signature = utils.generate_signature(
            method,
            path,
            query_string,
            headers,
            body,
            secret_key,
            now,
            region,
            service
        )

        query_string["X-Amz-Algorithm"]     = "AWS4-HMAC-SHA256"
        query_string["X-Amz-Credential"]    = credential
        query_string["X-Amz-Date"]          = amzdate
        query_string["X-Amz-Expires"]       = "86400"
        query_string["X-Amz-SignedHeaders"] = signed_headers
        query_string["X-Amz-Signature"]     = signature

        local query_string_list = {}
        for k,v in ipairs(query_string) do
            table.insert(query_string_list, k .. "=" .. v)
        end
        local query_string_str = ""
        if #query_string_list > 0 then
            query_string_str = "?" .. table.concat(query_string_list, "&")
        end

        local httpc = http.new()
        local uri = ngx.var.scheme .. "://" .. ngx.var.server_addr
        .. ":" .. ngx.var.server_port .. path
        local res, err = httpc:request_uri(uri,
            {
                method = method,
                body = body,
                keepalive = false,
                headers = headers,
                query = query_string
            }
        )

        ngx.status = res.status
        ngx.print(res.body)
    }
}
--- request
GET /t
--- error_code: 403
--- response_body
{"message":"Exceed body limit size"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: Exceed body limit size
