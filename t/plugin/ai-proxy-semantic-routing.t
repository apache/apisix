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

log_level("info");
repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    my $http_config = $block->http_config // <<_EOC_;
        # Mock embedding endpoint: returns a 2-D vector keyed on keywords so
        # tests can steer which instance a prompt matches.
        server {
            server_name mock_embedding;
            listen 6797;
            default_type 'application/json';
            location /v1/embeddings {
                content_by_lua_block {
                    local json = require("cjson.safe")
                    ngx.req.read_body()
                    -- the embedding call must not carry the client's headers
                    ngx.log(ngx.WARN, "embed-recv-cookie:",
                            ngx.var.http_cookie or "none")
                    local body = json.decode(ngx.req.get_body_data()) or {}
                    for _, t in ipairs(body.input or {}) do
                        if string.lower(t):find("servererror") then
                            -- an error body that echoes the prompt back, as some
                            -- providers do -- it must never reach our logs
                            ngx.status = 500
                            ngx.say('{"error":"bad input: ', t, ' SENSITIVE-ECHO"}')
                            return
                        elseif string.lower(t):find("scalarbody") then
                            -- 200 with a bare JSON null: decodes to a non-table,
                            -- which must not be indexed
                            ngx.status = 200
                            ngx.say("null")
                            return
                        elseif string.lower(t):find("scalarentry") then
                            -- 200 whose data array holds non-objects: indexing
                            -- item.index on a number would raise
                            ngx.status = 200
                            ngx.say('{"data":[1,2,3]}')
                            return
                        end
                    end
                    local function vec(text)
                        text = string.lower(text or "")
                        if text:find("code") or text:find("python") or text:find("debug") then
                            return {1, 0}
                        elseif text:find("translate") or text:find("summar") then
                            return {0, 1}
                        end
                        return {0.6, 0.6}
                    end
                    local data = {}
                    for i, t in ipairs(body.input or {}) do
                        if string.lower(t):find("malformed") then
                            -- emit a JSON null embedding (decodes to cjson.null)
                            -- to exercise fail-open on malformed data
                            data[i] = { index = i - 1, embedding = json.null }
                        elseif string.lower(t):find("dimmismatch") then
                            -- 3-D vector vs the 2-D reference vectors
                            data[i] = { index = i - 1, embedding = {1, 0, 0} }
                        else
                            data[i] = { index = i - 1, embedding = vec(t) }
                        end
                    end
                    ngx.status = 200
                    ngx.say(json.encode({ data = data }))
                }
            }
        }
        # Mock Azure OpenAI embeddings: the deployment and api-version live in
        # the URL, exactly as a real Azure endpoint requires.
        server {
            server_name mock_azure_embedding;
            listen 6799;
            default_type 'application/json';
            location /openai/deployments/emb/embeddings {
                content_by_lua_block {
                    local json = require("cjson.safe")
                    ngx.req.read_body()
                    -- prove the request reached the full Azure path with its query
                    -- (an nginx arg variable cannot express the hyphen)
                    local args = ngx.req.get_uri_args()
                    ngx.log(ngx.WARN, "azure-embed-hit api-version=",
                            args["api-version"] or "none")
                    local body = json.decode(ngx.req.get_body_data()) or {}
                    local data = {}
                    for i, t in ipairs(body.input or {}) do
                        local v = {0.6, 0.6}
                        if string.lower(t):find("code") or string.lower(t):find("python") then
                            v = {1, 0}
                        end
                        data[i] = { index = i - 1, embedding = v }
                    end
                    ngx.status = 200
                    ngx.say(json.encode({ data = data }))
                }
            }
        }
        # Mock LLM: echoes the model it received so tests can tell which
        # instance was selected.
        server {
            server_name mock_llm;
            listen 6798;
            default_type 'application/json';
            location /v1/chat/completions {
                content_by_lua_block {
                    local json = require("cjson.safe")
                    ngx.req.read_body()
                    local body = json.decode(ngx.req.get_body_data()) or {}
                    ngx.status = 200
                    ngx.print(body.model or "unknown")
                }
            }
        }
_EOC_
    $block->set_value("http_config", $http_config);

    my $user_yaml_config = <<_EOC_;
plugins:
  - ai-proxy-multi
_EOC_
    $block->set_value("extra_yaml_config", $user_yaml_config);
});

run_tests();

__DATA__

=== TEST 1: configure a semantic route (code / translate / catchall)
--- config
    location /t {
        content_by_lua_block {
            -- Build the config as a Lua table and core.json.encode it. A long
            -- inline JSON `[[ ]]` block that crosses nginx's config buffer
            -- boundary is misparsed by ngx_lua ("missing the closing long
            -- bracket"), so we keep the inlined Lua short instead.
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local function inst(name, model, examples, catchall)
                local i = {
                    name = name, provider = "openai", weight = 1,
                    auth = { header = { Authorization = "Bearer token" } },
                    options = { model = model },
                    override = {
                        endpoint = "http://127.0.0.1:6798/v1/chat/completions",
                    },
                }
                if examples then i.examples = examples end
                if catchall then i.catchall = true end
                return i
            end
            local conf = {
                uri = "/anything",
                plugins = {
                    ["ai-proxy-multi"] = {
                        embeddings = {
                            provider = "openai",
                            model = "text-embedding-3-small",
                            endpoint = "http://127.0.0.1:6797/v1/embeddings",
                            auth = { header = { Authorization = "Bearer token" } },
                            ssl_verify = false,
                        },
                        balancer = { algorithm = "semantic", threshold = 0.9 },
                        instances = {
                            inst("code", "model-code", {"write python code"}),
                            inst("cheap", "model-cheap", {"translate this text"}),
                            inst("default", "model-fallback", nil, true),
                        },
                        ssl_verify = false,
                    },
                },
            }
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT,
                                 core.json.encode(conf))
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed
--- no_error_log
[error]



=== TEST 2: coding prompt routes to the code model
--- request
POST /anything
{"model":"auto","messages":[{"role":"user","content":"help me debug this python code"}]}
--- more_headers
Content-Type: application/json
--- response_body chomp
model-code
--- no_error_log
[error]



=== TEST 3: translation prompt routes to the cheap model
--- request
POST /anything
{"model":"auto","messages":[{"role":"user","content":"please translate this to english"}]}
--- more_headers
Content-Type: application/json
--- response_body chomp
model-cheap
--- no_error_log
[error]



=== TEST 4: unrelated prompt clears no threshold, falls back to catchall
--- request
POST /anything
{"model":"auto","messages":[{"role":"user","content":"what is the weather today"}]}
--- more_headers
Content-Type: application/json
--- response_body chomp
model-fallback
--- error_log eval
qr/no instance cleared threshold \(scores: code:0\.\d+,cheap:0\.\d+\)/
--- no_error_log
[error]



=== TEST 5: malformed embedding fails open to catchall, not the matching instance
--- request
POST /anything
{"model":"auto","messages":[{"role":"user","content":"debug this python code, malformed"}]}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- response_body chomp
model-fallback
--- error_log
semantic routing: query embedding failed
--- no_error_log
[error]



=== TEST 6: reconfigure the route with expose_scores enabled
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local function inst(name, model, examples, catchall)
                local i = {
                    name = name, provider = "openai", weight = 1,
                    auth = { header = { Authorization = "Bearer token" } },
                    options = { model = model },
                    override = {
                        endpoint = "http://127.0.0.1:6798/v1/chat/completions",
                    },
                }
                if examples then i.examples = examples end
                if catchall then i.catchall = true end
                return i
            end
            local conf = {
                uri = "/anything",
                plugins = {
                    ["ai-proxy-multi"] = {
                        embeddings = {
                            provider = "openai",
                            model = "text-embedding-3-small",
                            endpoint = "http://127.0.0.1:6797/v1/embeddings",
                            auth = { header = { Authorization = "Bearer token" } },
                            ssl_verify = false,
                        },
                        balancer = {
                            algorithm = "semantic", threshold = 0.9,
                            expose_scores = true,
                        },
                        instances = {
                            inst("code", "model-code", {"write python code"}),
                            inst("cheap", "model-cheap", {"translate this text"}),
                            inst("default", "model-fallback", nil, true),
                        },
                        ssl_verify = false,
                    },
                },
            }
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT,
                                 core.json.encode(conf))
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed
--- no_error_log
[error]



=== TEST 7: debug exposes per-instance scores and the pick via headers
--- request
POST /anything
{"model":"auto","messages":[{"role":"user","content":"help me debug this python code"}]}
--- more_headers
Content-Type: application/json
--- response_body chomp
model-code
--- response_headers_like
X-AI-Semantic-Route: code
X-AI-Semantic-Scores: code:1\.\d+,cheap:0\.\d+
--- no_error_log
[error]



=== TEST 8: embedding dimension mismatch fails open to catchall
--- request
POST /anything
{"model":"auto","messages":[{"role":"user","content":"dimmismatch python code"}]}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- response_body chomp
model-fallback
--- error_log
embedding dimension mismatch
--- no_error_log
[error]



=== TEST 9: multimodal content array extracts text parts for routing
--- request
POST /anything
{"model":"auto","messages":[{"role":"user","content":[
{"type":"text","text":"write python code"},
{"type":"image_url","image_url":{"url":"http://x/y.png"}}
]}]}
--- more_headers
Content-Type: application/json
--- response_body chomp
model-code
--- no_error_log
[error]



=== TEST 10: client headers are not forwarded to the embedding endpoint
--- request
POST /anything
{"model":"auto","messages":[{"role":"user","content":"help me debug this python code"}]}
--- more_headers
Content-Type: application/json
Cookie: session=super-secret
--- response_body chomp
model-code
--- error_log
embed-recv-cookie:none
--- no_error_log
embed-recv-cookie:session=super-secret



=== TEST 11: non-200 fails open to catchall, without logging the upstream body
--- request
POST /anything
{"model":"auto","messages":[{"role":"user","content":"servererror python code"}]}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- response_body chomp
model-fallback
--- error_log
embedding endpoint returned status 500
--- no_error_log
SENSITIVE-ECHO



=== TEST 12: 200 with a non-table body fails open instead of raising
--- request
POST /anything
{"model":"auto","messages":[{"role":"user","content":"scalarbody python code"}]}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- response_body chomp
model-fallback
--- error_log
invalid embedding response
--- no_error_log
[error]



=== TEST 13: 200 whose data array holds non-objects fails open instead of raising
--- request
POST /anything
{"model":"auto","messages":[{"role":"user","content":"scalarentry python code"}]}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- response_body chomp
model-fallback
--- error_log
invalid embedding entry at index 0
--- no_error_log
[error]



=== TEST 14: reference embedding failure fails open to catchall
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local function inst(name, model, examples, catchall)
                local i = {
                    name = name, provider = "openai", weight = 1,
                    auth = { header = { Authorization = "Bearer token" } },
                    options = { model = model },
                    override = {
                        endpoint = "http://127.0.0.1:6798/v1/chat/completions",
                    },
                }
                if examples then i.examples = examples end
                if catchall then i.catchall = true end
                return i
            end
            local conf = {
                uri = "/anything",
                plugins = {
                    ["ai-proxy-multi"] = {
                        embeddings = {
                            provider = "openai",
                            model = "text-embedding-3-small",
                            endpoint = "http://127.0.0.1:6797/v1/embeddings",
                            auth = { header = { Authorization = "Bearer token" } },
                            ssl_verify = false,
                        },
                        balancer = { algorithm = "semantic", threshold = 0.9 },
                        instances = {
                            -- embedding this instance's examples makes the mock
                            -- fail the whole reference batch
                            inst("code", "model-code", {"servererror example"}),
                            inst("default", "model-fallback", nil, true),
                        },
                        ssl_verify = false,
                    },
                },
            }
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT,
                                 core.json.encode(conf))
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed
--- no_error_log
[error]



=== TEST 15: request on the broken-reference route still routes to catchall
--- request
POST /anything
{"model":"auto","messages":[{"role":"user","content":"help me debug this python code"}]}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- response_body chomp
model-fallback
--- error_log
failed to fetch reference embeddings
--- no_error_log
[error]



=== TEST 16: azure-openai embeddings route via the full deployment URL
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local function inst(name, model, examples, catchall)
                local i = {
                    name = name, provider = "openai", weight = 1,
                    auth = { header = { Authorization = "Bearer token" } },
                    options = { model = model },
                    override = {
                        endpoint = "http://127.0.0.1:6798/v1/chat/completions",
                    },
                }
                if examples then i.examples = examples end
                if catchall then i.catchall = true end
                return i
            end
            local conf = {
                uri = "/anything",
                plugins = {
                    ["ai-proxy-multi"] = {
                        embeddings = {
                            provider = "azure-openai",
                            model = "text-embedding-3-small",
                            endpoint = "http://127.0.0.1:6799/openai/deployments/emb"
                                       .. "/embeddings?api-version=2024-02-01",
                            auth = { header = { ["api-key"] = "azure-key" } },
                            ssl_verify = false,
                        },
                        balancer = { algorithm = "semantic", threshold = 0.9 },
                        instances = {
                            inst("code", "model-code", {"write python code"}),
                            inst("default", "model-fallback", nil, true),
                        },
                        ssl_verify = false,
                    },
                },
            }
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT,
                                 core.json.encode(conf))
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed
--- no_error_log
[error]



=== TEST 17: azure embeddings request reaches the deployment path with api-version
--- request
POST /anything
{"model":"auto","messages":[{"role":"user","content":"help me debug this python code"}]}
--- more_headers
Content-Type: application/json
--- response_body chomp
model-code
--- error_log
azure-embed-hit api-version=2024-02-01
--- no_error_log
[error]



=== TEST 18: no catchall configured -- fallback is the first instance
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local function inst(name, model, examples)
                return {
                    name = name, provider = "openai", weight = 1,
                    auth = { header = { Authorization = "Bearer token" } },
                    options = { model = model },
                    override = {
                        endpoint = "http://127.0.0.1:6798/v1/chat/completions",
                    },
                    examples = examples,
                }
            end
            local conf = {
                uri = "/anything",
                plugins = {
                    ["ai-proxy-multi"] = {
                        embeddings = {
                            provider = "openai",
                            model = "text-embedding-3-small",
                            endpoint = "http://127.0.0.1:6797/v1/embeddings",
                            auth = { header = { Authorization = "Bearer token" } },
                            ssl_verify = false,
                        },
                        balancer = { algorithm = "semantic", threshold = 0.9 },
                        instances = {
                            inst("first", "model-first", {"write python code"}),
                            inst("second", "model-second", {"translate this text"}),
                        },
                        ssl_verify = false,
                    },
                },
            }
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT,
                                 core.json.encode(conf))
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed
--- no_error_log
[error]



=== TEST 19: unmatched prompt falls back to the first instance
--- request
POST /anything
{"model":"auto","messages":[{"role":"user","content":"what is the weather today"}]}
--- more_headers
Content-Type: application/json
--- response_body chomp
model-first
--- error_log
no instance cleared threshold
--- no_error_log
[error]



=== TEST 20: per-instance threshold overrides the global one
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local conf = {
                uri = "/anything",
                plugins = {
                    ["ai-proxy-multi"] = {
                        embeddings = {
                            provider = "openai",
                            model = "text-embedding-3-small",
                            endpoint = "http://127.0.0.1:6797/v1/embeddings",
                            auth = { header = { Authorization = "Bearer token" } },
                            ssl_verify = false,
                        },
                        -- the global threshold is permissive (0.1); the code
                        -- instance raises its own bar to 0.9, so a prompt scoring
                        -- ~0.707 clears the global one but not the instance's
                        balancer = { algorithm = "semantic", threshold = 0.1 },
                        instances = {
                            {
                                name = "code", provider = "openai", weight = 1,
                                auth = { header = { Authorization = "Bearer token" } },
                                options = { model = "model-code" },
                                override = {
                                    endpoint = "http://127.0.0.1:6798/v1/chat/completions",
                                },
                                examples = {"write python code"},
                                threshold = 0.9,
                            },
                            {
                                name = "default", provider = "openai", weight = 1,
                                auth = { header = { Authorization = "Bearer token" } },
                                options = { model = "model-fallback" },
                                override = {
                                    endpoint = "http://127.0.0.1:6798/v1/chat/completions",
                                },
                                catchall = true,
                            },
                        },
                        ssl_verify = false,
                    },
                },
            }
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT,
                                 core.json.encode(conf))
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed
--- no_error_log
[error]



=== TEST 21: a prompt below the per-instance threshold reaches the catchall
--- request
POST /anything
{"model":"auto","messages":[{"role":"user","content":"what is the weather today"}]}
--- more_headers
Content-Type: application/json
--- response_body chomp
model-fallback
--- no_error_log
[error]
