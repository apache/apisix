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

=== TEST 1: Verify by Header: add consumer with plugin aws-auth
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



=== TEST 2: Verify by Header: add aws auth plugin using admin api
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



=== TEST 3: Verify by Header: missing header Authentication
--- request
GET /hello
--- error_code: 403
--- response_body
{"message":"Missing Authentication Token"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: Missing Authentication Token



=== TEST 4: Verify by Header: empty Authentication header
--- request
GET /hello
--- more_headers
Host: examplebucket.s3.amazonaws.com
Authorization:
Range: bytes=0-9
x-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
x-amz-date: 20130524T000000Z
--- error_code: 403
--- response_body
{"message":"Authorization header cannot be empty: ''"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: Authorization header cannot be empty: ''



=== TEST 5: Verify by Header: Bad Authorization Header
--- request
GET /hello
--- more_headers
Host: examplebucket.s3.amazonaws.com
Authorization: Bearer XXXXXXXXXXXXXXXXXXX
Range: bytes=0-9
x-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
x-amz-date: 20130524T000000Z
--- error_code: 403
--- response_body
{"message":"Bad Authorization Header"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: Bad Authorization Header



=== TEST 6: Verify by Header: Credential: algorithm mistake
--- request
GET /hello
--- more_headers
Host: examplebucket.s3.amazonaws.com
Authorization: FAKE-ALGO Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request,SignedHeaders=host;range;x-amz-content-sha256;x-amz-date,Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41
Range: bytes=0-9
x-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
x-amz-date: 20130524T000000Z
--- error_code: 403
--- response_body
{"message":"algorithm 'FAKE-ALGO' is not supported"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: algorithm 'FAKE-ALGO' is not supported



=== TEST 7: Verify by Header: Credential: access key missing
--- request
GET /hello
--- more_headers
Host: examplebucket.s3.amazonaws.com
Authorization: AWS4-HMAC-SHA256 Credential=/20130524/us-east-1/s3/aws4_request,SignedHeaders=host;range;x-amz-content-sha256;x-amz-date,Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41
Range: bytes=0-9
x-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
x-amz-date: 20130524T000000Z
--- error_code: 403
--- response_body
{"message":"access key missing"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: access key missing



=== TEST 8: Verify by Header: Credential: date missing
--- request
GET /hello
--- more_headers
Host: examplebucket.s3.amazonaws.com
Authorization: AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE//us-east-1/s3/aws4_request,SignedHeaders=host;range;x-amz-content-sha256;x-amz-date,Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41
Range: bytes=0-9
x-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
x-amz-date: 20130524T000000Z
--- error_code: 403
--- response_body
{"message":"date missing"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: date missing



=== TEST 9: Verify by Header: Credential: region missing
--- request
GET /hello
--- more_headers
Host: examplebucket.s3.amazonaws.com
Authorization: AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524//s3/aws4_request,SignedHeaders=host;range;x-amz-content-sha256;x-amz-date,Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41
Range: bytes=0-9
x-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
x-amz-date: 20130524T000000Z
--- error_code: 403
--- response_body
{"message":"region missing"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: region missing



=== TEST 10: Verify by Header: Credential: invalid region
--- request
GET /hello
--- more_headers
Host: examplebucket.s3.amazonaws.com
Authorization: AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/fake-region/s3/aws4_request,SignedHeaders=host;range;x-amz-content-sha256;x-amz-date,Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41
Range: bytes=0-9
x-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
x-amz-date: 20130524T000000Z
--- error_code: 403
--- response_body
{"message":"Credential should be scoped to a valid Region, not 'fake-region'"}
--- grep_error_log eval
qr/client request can't be validated: Credential should be scoped to a valid Region, not [^,]+/
--- grep_error_log_out
client request can't be validated: Credential should be scoped to a valid Region, not 'fake-region'



=== TEST 11: Verify by Header: Credential: service missing
--- request
GET /hello
--- more_headers
Host: examplebucket.s3.amazonaws.com
Authorization: AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1//aws4_request,SignedHeaders=host;range;x-amz-content-sha256;x-amz-date,Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41
Range: bytes=0-9
x-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
x-amz-date: 20130524T000000Z
--- error_code: 403
--- response_body
{"message":"service missing"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: service missing



=== TEST 12: Verify by Header: Credential: invalid service
--- request
GET /hello
--- more_headers
Host: examplebucket.s3.amazonaws.com
Authorization: AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/fake-service/aws4_request,SignedHeaders=host;range;x-amz-content-sha256;x-amz-date,Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41
Range: bytes=0-9
x-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
x-amz-date: 20130524T000000Z
--- error_code: 403
--- response_body
{"message":"Credential should be scoped to correct service: 'fake-service'"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: Credential should be scoped to correct service: 'fake-service'



=== TEST 13: Verify by Header: Credential: invalid terminator
--- request
GET /hello
--- more_headers
Host: examplebucket.s3.amazonaws.com
Authorization: AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/not_aws4_request,SignedHeaders=host;range;x-amz-content-sha256;x-amz-date,Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41
Range: bytes=0-9
x-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
x-amz-date: 20130524T000000Z
--- error_code: 403
--- response_body
{"message":"Credential should be scoped with a valid terminator: 'aws4_request'"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: Credential should be scoped with a valid terminator: 'aws4_request'



=== TEST 14: Verify by Header: signed_header: Host missing
--- request
GET /hello
--- more_headers
Host: examplebucket.s3.amazonaws.com
Authorization: AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request,SignedHeaders=range;x-amz-content-sha256;x-amz-date,Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41
Range: bytes=0-9
x-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
x-amz-date: 20130524T000000Z
--- error_code: 403
--- response_body
{"message":"header 'Host' is not signed"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: header 'Host' is not signed



=== TEST 15: Verify by Header: signed_header: X-Amz-Date missing
--- request
GET /hello
--- more_headers
Host: examplebucket.s3.amazonaws.com
Authorization: AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request,SignedHeaders=host;range;x-amz-content-sha256,Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41
Range: bytes=0-9
x-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
x-amz-date: 20130524T000000Z
--- error_code: 403
--- response_body
{"message":"header 'X-Amz-Date' is not signed"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: header 'X-Amz-Date' is not signed



=== TEST 16: Verify by Header: clock_skew: Date in Credential scope is dismatch X-Amz-Date parameter
--- request
GET /hello
--- more_headers
Host: examplebucket.s3.amazonaws.com
Authorization: AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request,SignedHeaders=host;range;x-amz-content-sha256;x-amz-date,Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41
Range: bytes=0-9
x-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
x-amz-date: 20000101T000000Z
--- error_code: 403
--- response_body
{"message":"Date in Credential scope does not match YYYYMMDD from ISO-8601 version of date from HTTP"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: Date in Credential scope does not match YYYYMMDD from ISO-8601 version of date from HTTP



=== TEST 17: Verify by Header: clock_skew: Signature expired
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

        local query_string = {}

        local headers = {}
        headers["Host"]                 = "examplebucket.s3.amazonaws.com"
        headers["x-amz-date"]           = amzdate
        headers["x-amz-content-sha256"] = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

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

        local _, signed_headers = utils.build_canonical_headers(headers)
        headers["Authorization"] = "AWS4-HMAC-SHA256 "
        .. "Credential=" .. credential .. ","
        .. "SignedHeaders=" .. signed_headers .. ","
        .. "Signature=" .. signature

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



=== TEST 18: Verify by Header: clock_skew: Signature in the future
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

        local query_string = {}

        local headers = {}
        headers["Host"]                 = "examplebucket.s3.amazonaws.com"
        headers["x-amz-date"]           = amzdate
        headers["x-amz-content-sha256"] = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
       

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

        local _, signed_headers = utils.build_canonical_headers(headers)
        headers["Authorization"] = "AWS4-HMAC-SHA256 "
        .. "Credential=" .. credential .. ","
        .. "SignedHeaders=" .. signed_headers .. ","
        .. "Signature=" .. signature

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



=== TEST 19: Verify by Header: Success
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
        local access_key =  "AKIAIOSFODNN7EXAMPLE"
        local secret_key =  "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
        local region     = "us-east-1"
        local service    = "s3"
        local credential = table.concat({access_key, datestamp, region, service, "aws4_request"}, "/")

        local query_string = {}

        local headers = {}
        headers["Host"] = "examplebucket.s3.amazonaws.com"
        headers["x-amz-date"] = amzdate
        headers["x-amz-content-sha256"] = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

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

        local _, signed_headers = utils.build_canonical_headers(headers)
        headers["Authorization"] = "AWS4-HMAC-SHA256 "
        .. "Credential=" .. credential .. ","
        .. "SignedHeaders=" .. signed_headers .. ","
        .. "Signature=" .. signature

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



=== TEST 20: Verify by Header: Consumer not found
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

        local query_string = {}

        local headers = {}
        headers["Host"] = "examplebucket.s3.amazonaws.com"
        headers["x-amz-date"] = amzdate
        headers["x-amz-content-sha256"] = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

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

        local _, signed_headers = utils.build_canonical_headers(headers)
        headers["Authorization"] = "AWS4-HMAC-SHA256 "
        .. "Credential=" .. credential .. ","
        .. "SignedHeaders=" .. signed_headers .. ","
        .. "Signature=" .. signature

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



=== TEST 21: Verify by Header: Signature Dismatch
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

        local query_string = {}

        local headers = {}
        headers["Host"] = "examplebucket.s3.amazonaws.com"
        headers["x-amz-date"] = amzdate
        headers["x-amz-content-sha256"] = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

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

        local _, signed_headers = utils.build_canonical_headers(headers)
        headers["Authorization"] = "AWS4-HMAC-SHA256 "
        .. "Credential=" .. credential .. ","
        .. "SignedHeaders=" .. signed_headers .. ","
        .. "Signature=" .. signature

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



=== TEST 22: Verify by Header: Exceed body limit size
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
        local secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
        local region     = "us-east-1"
        local service    = "s3"
        local credential = table.concat({access_key, datestamp, region, service, "aws4_request"}, "/")

        local query_string = {}

        local headers = {}
        headers["Host"] = "examplebucket.s3.amazonaws.com"
        headers["x-amz-date"] = amzdate
        headers["x-amz-content-sha256"] = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"


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

        local _, signed_headers = utils.build_canonical_headers(headers)
        headers["Authorization"] = "AWS4-HMAC-SHA256 "
        .. "Credential=" .. credential .. ","
        .. "SignedHeaders=" .. signed_headers .. ","
        .. "Signature=" .. signature

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
