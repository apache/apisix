--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--

local core = require("apisix.core")
local secret = require("apisix.secret")
local schema = require("apisix.plugins.ai-proxy.schema")
local base   = require("apisix.plugins.ai-proxy.base")
local plugin = require("apisix.plugin")
local ipmatcher  = require("resty.ipmatcher")
local healthcheck_manager = require("apisix.healthcheck_manager")
local resource = require("apisix.resource")
local exporter = require("apisix.plugins.prometheus.exporter")
local tonumber = tonumber
local pairs = pairs
local table_sort = table.sort
local table_concat = table.concat
local math_random = math.random
local ngx_now = ngx.now

local require = require
local pcall = pcall
local error = error
local tostring = tostring
local ipairs = ipairs
local type = type
local string = string
local sub = string.sub
local url = require("socket.url")

local priority_balancer = require("apisix.balancer.priority")
local semantic = require("apisix.plugins.ai-proxy.semantic")
local embedding = require("apisix.plugins.ai-proxy.embedding")
local endpoint_regex = "^(https?)://([^:/]+):?(%d*)/?.*$"

local pickers = {}
local lrucache_server_picker = core.lrucache.new({
    ttl = 300, count = 256
})
local lrucache_health_status = core.lrucache.new({
    ttl = 300, count = 256
})
-- Keyed by route + conf version, so config changes invalidate immediately;
-- the long ttl just avoids re-embedding references on unchanged config.
local lrucache_semantic_vectors = core.lrucache.new({
    ttl = 3600, count = 256
})
-- The prompt is sent verbatim to a third-party embedding endpoint. Bound it: a
-- request body may be up to max_req_body_size (64MB by default), and an oversized
-- input would blow the embedding model's token limit, 400, and silently push every
-- large prompt to the catchall. Routing intent lives in the opening sentences.
local MAX_EMBED_PROMPT_BYTES = 8192

local plugin_name = "ai-proxy-multi"
local _M = {
    version = 0.5,
    priority = 1041,
    name = plugin_name,
    schema = schema.ai_proxy_multi_schema,
}

local function fallback_strategy_has(strategy, name)
    if not strategy then
        return false
    end

    if type(strategy) == "string" then
        return strategy == name
    end

    if type(strategy) == "table" then
        for _, v in ipairs(strategy) do
            if v == name then
                return true
            end
        end
    end

    return false
end


local function get_chash_key_schema(hash_on)
    if hash_on == "vars" then
        return core.schema.upstream_hash_vars_schema
    end

    if hash_on == "header" or hash_on == "cookie" then
        return core.schema.upstream_hash_header_schema
    end

    if hash_on == "consumer" then
        return nil, nil
    end

    if hash_on == "vars_combinations" then
        return core.schema.upstream_hash_vars_combinations_schema
    end

    return nil, "invalid hash_on type " .. hash_on
end


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema.ai_proxy_multi_schema, conf)
    if not ok then
        return false, err
    end

    for _, instance in ipairs(conf.instances) do
        local endpoint = instance and instance.override and instance.override.endpoint
        if endpoint then
            local scheme, host, _ = endpoint:match(endpoint_regex)
            if not scheme or not host  then
                return false, "invalid endpoint"
            end
        end
        local ai_provider, err = pcall(require, "apisix.plugins.ai-providers." .. instance.provider)
        if not ai_provider then
            core.log.warn("fail to require ai provider: ", instance.provider, ", err", err)
            return false, "ai provider: " .. instance.provider .. " is not supported."
        end
        local sa_json = core.table.try_read_attr(instance, "auth", "gcp", "service_account_json")
        if sa_json and not secret.is_secret_ref(sa_json) then
            local _, err = core.json.decode(sa_json)
            if err then
                return false, "invalid gcp service_account_json: " .. err
            end
        end
        local ok, err = schema.validate_provider_requirements(instance)
        if not ok then
            return false, "instance '" .. (instance.name or "?") .. "': " .. err
        end
    end
    local algo = core.table.try_read_attr(conf, "balancer", "algorithm")
    local hash_on = core.table.try_read_attr(conf, "balancer", "hash_on")
    local hash_key = core.table.try_read_attr(conf, "balancer", "key")

    if type(algo) == "string" and algo == "chash" then
        if not hash_on then
            return false, "must configure `hash_on` when balancer algorithm is chash"
        end

        if hash_on ~= "consumer" and not hash_key then
            return false, "must configure `hash_key` when balancer `hash_on` is not set to cookie"
        end

        local key_schema, err = get_chash_key_schema(hash_on)
        if err then
            return false, "type is chash, err: " .. err
        end

        if key_schema then
            local ok, err = core.schema.check(key_schema, hash_key)
            if not ok then
                return false, "invalid configuration: " .. err
            end
        end
    end

    if algo == "semantic" then
        if not conf.embeddings then
            return false, "must configure `embeddings` when balancer algorithm is semantic"
        end
        -- Same scheme+host check the instance endpoints get: without it an
        -- endpoint like "host/path" parses to a nil host and every request would
        -- silently fail open, i.e. the route would never work with no signal.
        local eendpoint = conf.embeddings.endpoint
        if eendpoint then
            local scheme, host = eendpoint:match(endpoint_regex)
            if not scheme or not host then
                return false, "invalid `embeddings.endpoint`"
            end
        end
        if conf.embeddings.provider == "azure-openai" then
            -- Azure carries the deployment in the URL and declares no default host
            -- or path, so the endpoint must be the full embeddings URL. Without a
            -- path every request would silently fail open to the catchall.
            if not eendpoint then
                return false, "must configure `embeddings.endpoint` when embeddings " ..
                    "provider is azure-openai"
            end
            local parsed = url.parse(eendpoint)
            local epath = parsed and parsed.path
            if not epath or epath == "" or epath == "/" then
                return false, "`embeddings.endpoint` for azure-openai must include the " ..
                    "full deployment path, e.g. https://{resource}.openai.azure.com" ..
                    "/openai/deployments/{deployment}/embeddings?api-version=..."
            end
        end
        local catchall_count = 0
        for _, instance in ipairs(conf.instances) do
            if instance.catchall then
                catchall_count = catchall_count + 1
                -- The catchall is the fallback target, never a ranking candidate.
                -- Allowing examples on it would let it outrank a real match.
                if instance.examples then
                    return false, "instance '" .. (instance.name or "?") ..
                        "': `catchall` instance must not configure `examples`; it is " ..
                        "the fallback target and does not take part in ranking"
                end
            else
                local has_example = false
                if instance.examples then
                    for _, ex in ipairs(instance.examples) do
                        if type(ex) == "string" and ex ~= "" then
                            has_example = true
                            break
                        end
                    end
                end
                if not has_example then
                    return false, "instance '" .. (instance.name or "?") ..
                        "': must configure non-empty `examples` for the semantic " ..
                        "algorithm unless `catchall` is set"
                end
            end
        end
        if catchall_count > 1 then
            return false, "at most one instance may be marked `catchall`"
        end
    end

    return true
end


local function transform_instances(new_instances, instance)
    if not new_instances._priority_index then
        new_instances._priority_index = {}
    end

    if not new_instances[instance.priority] then
        new_instances[instance.priority] = {}
        core.table.insert(new_instances._priority_index, instance.priority)
    end

    new_instances[instance.priority][instance.name] = instance.weight
end

local function sort_nodes(a, b)
    if a.host == b.host then
        return (a.port or 0) < (b.port or 0)
    end
    return a.host < b.host
end


local function nodes_equal(old_nodes, new_nodes)
    if old_nodes == new_nodes then
        return true
    end

    if type(old_nodes) ~= "table" or #old_nodes ~= #new_nodes then
        return false
    end

    for i, new_node in ipairs(new_nodes) do
        local old_node = old_nodes[i]
        for _, field in ipairs({"host", "port", "scheme", "domain"}) do
            if old_node[field] ~= new_node[field] then
                return false
            end
        end
    end

    return true
end


local function parse_domain_for_nodes(node)
    local host = node.domain or node.host
    if not ipmatcher.parse_ipv4(host)
       and not ipmatcher.parse_ipv6(host)
    then
        local ips, err = core.resolver.parse_domain_all(host)
        if err then
            core.log.error("dns resolver domain: ", host, " error: ", err)
        end

        if ips then
            local nodes = core.table.new(#ips, 0)
            for _, ip in ipairs(ips) do
                local new_node = core.table.clone(node)
                new_node.host = ip
                new_node.domain = host
                core.table.insert(nodes, new_node)
            end
            table_sort(nodes, sort_nodes)
            return nodes
        end
    end

    return {node}
end


local function make_endpoint(node)
    local host = node.host
    if ipmatcher.parse_ipv6(host) then
        host = "[" .. host .. "]"
    end

    local endpoint = node.scheme .. "://" .. host .. ":" .. node.port
    if node.path then
        endpoint = endpoint .. node.path
    end
    if node.query then
        endpoint = endpoint .. "?" .. node.query
    end
    return endpoint
end


local function make_host_header(node)
    if not node.domain then
        return nil
    end

    local port = tonumber(node.port)
    if (node.scheme == "https" and port ~= 443)
       or (node.scheme ~= "https" and port ~= 80)
    then
        return node.domain .. ":" .. node.port
    end

    return node.domain
end


local function use_node_for_request(instance_conf, node)
    if not node then
        return
    end

    instance_conf._dns_value = node
    instance_conf._resolved_endpoint = make_endpoint(node)
    instance_conf._resolved_host_header = make_host_header(node)
    instance_conf._resolved_ssl_server_name = node.domain
end


local function pick_request_node(nodes)
    if not nodes or #nodes == 0 then
        return
    end

    return nodes[math_random(1, #nodes)]
end


-- resolves endpoint and sets it on _dns_nodes
local function resolve_endpoint(instance_conf)
    local scheme, host, port, path, query
    local endpoint = core.table.try_read_attr(instance_conf, "override", "endpoint")
    if endpoint then
        local parsed = url.parse(endpoint)
        scheme = parsed.scheme
        host = parsed.host
        port = parsed.port
        path = parsed.path
        query = parsed.query
        if not port then
            port = (scheme == "https") and 443 or 80
        end
        port = tonumber(port)
    else
        local ai_provider = require("apisix.plugins.ai-providers." .. instance_conf.provider)
        if ai_provider.get_node then
            local node = ai_provider.get_node(instance_conf)
            host = node.host
            port = node.port
        else
            host = ai_provider.host
            port = ai_provider.port
        end
        scheme = "https"
    end

    local new_node = {
        host = host,
        port = port,
        scheme = scheme,
        path = path,
        query = query,
    }
    local new_nodes = parse_domain_for_nodes(new_node)

    local nodes_changed = not nodes_equal(instance_conf._dns_nodes, new_nodes)

    if nodes_changed then
        instance_conf._dns_nodes = new_nodes
        instance_conf._nodes_ver = (instance_conf._nodes_ver or 0) + 1
        core.log.info("DNS resolution changed for instance: ", instance_conf.name,
                     " new nodes: ", core.json.delay_encode(new_nodes))
    end

    use_node_for_request(instance_conf, pick_request_node(instance_conf._dns_nodes))
end


local function get_checkers_status_ver(conf, checkers)
    local parts = core.table.new(#conf.instances, 0)
    for i, ins in ipairs(conf.instances) do
        local checker = checkers[ins.name]
        -- "x" distinguishes "checker not created yet" from a created checker
        -- whose status_ver is still 0. Otherwise the server picker built
        -- without health filtering before the checker exists would share the
        -- same cache key with the post-creation state and be reused even
        -- after the shm already marks some nodes unhealthy.
        parts[i] = checker and checker.status_ver or "x"
    end
    return table_concat(parts, "-")
end


local function fetch_all_instances(conf)
    local instances = conf.instances
    local new_instances = core.table.new(0, #instances)
    for _, ins in ipairs(instances) do
        transform_instances(new_instances, ins)
    end

    return new_instances
end


local function create_health_status(conf, checkers)
    local instances = conf.instances
    local health_status = core.table.new(0, #instances)
    local healthy_dns_nodes = core.table.new(0, #instances)
    local has_healthy_instance = false

    for _, ins in ipairs(instances) do
        local checker = checkers[ins.name]
        if checker then
            local host = ins.checks and ins.checks.active and ins.checks.active.host
            local port = ins.checks and ins.checks.active and ins.checks.active.port
            local healthy_nodes = {}

            for _, node in ipairs(ins._dns_nodes or {}) do
                local ok, err = healthcheck_manager.fetch_node_status(checker,
                                                     node.host, port or node.port, host)
                if ok then
                    healthy_nodes[#healthy_nodes + 1] = node
                elseif err then
                    core.log.warn("failed to get health check target status, addr: ",
                        node.host, ":", port or node.port, ", host: ", host, ", err: ", err)
                end
            end

            if #healthy_nodes > 0 then
                healthy_dns_nodes[ins.name] = healthy_nodes
                health_status[ins.name] = true
                has_healthy_instance = true
            else
                health_status[ins.name] = false
            end
        else
            health_status[ins.name] = true
            has_healthy_instance = true
        end
    end

    if not has_healthy_instance then
        core.log.warn("all upstream nodes is unhealthy, use default")
        return {all_unhealthy = true}
    end

    return {
        status = health_status,
        healthy_dns_nodes = healthy_dns_nodes,
    }
end


local function apply_health_status(conf, health_status)
    if not health_status or health_status.all_unhealthy then
        for _, ins in ipairs(conf.instances) do
            ins._healthy_dns_nodes = nil
        end

        return nil
    end

    for _, ins in ipairs(conf.instances) do
        ins._healthy_dns_nodes = health_status.healthy_dns_nodes[ins.name]
    end

    return health_status.status
end


-- Build the picker instance set from the healthy subset, reusing
-- create_health_status/apply_health_status so the per-instance health lookup
-- lives in exactly one place.
local function fetch_health_instances(conf, checkers)
    if not checkers then
        return fetch_all_instances(conf)
    end

    local status = apply_health_status(conf, create_health_status(conf, checkers))
    if not status then
        return fetch_all_instances(conf)
    end

    local new_instances = core.table.new(0, #conf.instances)
    for _, ins in ipairs(conf.instances) do
        if status[ins.name] then
            transform_instances(new_instances, ins)
        end
    end

    return new_instances
end


local function get_health_status_ver(conf, checkers)
    local parts = core.table.new(#conf.instances, 0)
    for i, ins in ipairs(conf.instances) do
        local checker = checkers[ins.name]
        parts[i] = (ins._nodes_ver or 0) .. ":" .. (checker and checker.status_ver or "x")
    end

    return table_concat(parts, "-")
end


local function fetch_health_status(conf, checkers, key, version)
    if not checkers then
        return nil
    end

    local health_status = lrucache_health_status(key, version .. "#" ..
                                                 get_health_status_ver(conf, checkers),
                                                 create_health_status, conf, checkers)
    return apply_health_status(conf, health_status)
end


local function create_server_picker(conf, ups_tab, checkers)
    local picker = pickers[conf.balancer.algorithm] -- nil check
    if not picker then
        pickers[conf.balancer.algorithm] = require("apisix.balancer." .. conf.balancer.algorithm)
        picker = pickers[conf.balancer.algorithm]
    end

    local new_instances
    if conf.balancer.algorithm == "chash" then
        new_instances = fetch_all_instances(conf)
    else
        new_instances = fetch_health_instances(conf, checkers)
    end
    core.log.info("fetch health instances: ", core.json.delay_encode(new_instances))

    if #new_instances._priority_index > 1 then
        core.log.info("new instances: ", core.json.delay_encode(new_instances))
        return priority_balancer.new(new_instances, ups_tab, picker)
    end
    core.log.info("upstream nodes: ",
                core.json.delay_encode(new_instances[new_instances._priority_index[1]]))
    return picker.new(new_instances[new_instances._priority_index[1]], ups_tab)
end


local function get_instance_conf(instances, name)
    for _, ins in ipairs(instances) do
        if ins.name == name then
            return ins
        end
    end
end


local function pick_target(ctx, conf, ups_tab)
    local checkers = {}
    local res_conf = resource.fetch_latest_conf(conf._meta.parent.resource_key)
    if not res_conf then
        return nil, nil, "failed to fetch the parent config"
    end
    local instances = res_conf.value.plugins[plugin_name].instances
    for i, instance in ipairs(conf.instances) do
        if instance.checks then
            resolve_endpoint(instance)
            -- json path is 0 indexed so we need to decrement i
            local resource_path = conf._meta.parent.resource_key ..
                                  "#plugins['ai-proxy-multi'].instances[" .. i-1 .. "]"
            local resource_version = conf._meta.parent.resource_version
            if instance._nodes_ver then
                resource_version = resource_version .. instance._nodes_ver
            end
            instances[i]._dns_nodes = instance._dns_nodes
            instances[i]._nodes_ver = instance._nodes_ver
            local checker = healthcheck_manager.fetch_checker(resource_path, resource_version)
            checkers[instance.name] = checker
        end
    end

    local health_status
    local version = plugin.conf_version(conf)
    if conf.balancer.algorithm == "chash" then
        health_status = fetch_health_status(conf, checkers, ctx.matched_route.key, version)
    else
        version = version .. "#" .. get_checkers_status_ver(conf, checkers)
    end

    local server_picker = ctx.server_picker
    if not server_picker then
        server_picker = lrucache_server_picker(ctx.matched_route.key, version,
                                               create_server_picker, conf, ups_tab, checkers)
    end
    if not server_picker then
        return nil, nil, "failed to fetch server picker"
    end
    ctx.server_picker = server_picker

    local ai_rate_limiting
    local check_rate_limiting = conf.fallback_strategy == "instance_health_and_rate_limiting" or
                                fallback_strategy_has(conf.fallback_strategy, "rate_limiting")
    if check_rate_limiting then
        ai_rate_limiting = require("apisix.plugins.ai-rate-limiting")
    end

    local instance_name, err
    for _ = 1, #conf.instances do
        instance_name, err = server_picker.get(ctx)
        if err then
            return nil, nil, err
        end

        if not health_status or health_status[instance_name] then
            if not check_rate_limiting or
               ai_rate_limiting.check_instance_status(nil, ctx, instance_name) then
                break
            end
            core.log.warn("ai instance: ", instance_name,
                             " is not available, try to pick another one")

        else
            core.log.warn("ai instance: ", instance_name,
                             " is unhealthy, try to pick another one")
        end

        ctx.balancer_server = instance_name
        if not server_picker.after_balance then
            return nil, nil, "failed to skip AI instance: after_balance is unavailable"
        end

        server_picker.after_balance(ctx, true)
        instance_name = nil
    end

    if not instance_name then
        return nil, nil, "all servers tried"
    end

    ctx.balancer_server = instance_name

    local instance_conf = get_instance_conf(conf.instances, instance_name)
    local nodes = instance_conf._healthy_dns_nodes or instance_conf._dns_nodes
    use_node_for_request(instance_conf, pick_request_node(nodes))
    return instance_name, instance_conf
end


local function extract_last_user_message()
    local body = core.request.get_json_request_body_table()
    if not body or type(body.messages) ~= "table" then
        return nil
    end
    for i = #body.messages, 1, -1 do
        local m = body.messages[i]
        if type(m) == "table" and m.role == "user" then
            local content = m.content
            if type(content) == "string" then
                return content
            elseif type(content) == "table" then
                -- multimodal content: concatenate the text parts so routing
                -- still works for {type=text|image_url,...} arrays.
                local parts = {}
                for _, p in ipairs(content) do
                    if type(p) == "table" and p.type == "text"
                       and type(p.text) == "string" then
                        parts[#parts + 1] = p.text
                    end
                end
                if #parts > 0 then
                    return table_concat(parts, " ")
                end
            end
        end
    end
    return nil
end


-- Embed every instance's examples in one batch and group the normalized
-- reference vectors by instance name. Raises on embedding failure so the
-- lrucache below does not cache a bad result.
local function build_instance_vectors(conf)
    local texts = {}
    local owners = {}
    for _, inst in ipairs(conf.instances) do
        if inst.examples then
            for _, ex in ipairs(inst.examples) do
                texts[#texts + 1] = ex
                owners[#texts] = inst.name
            end
        end
    end

    local vecs, err = embedding.fetch(conf.embeddings, texts)
    if not vecs then
        error("failed to fetch reference embeddings: " .. tostring(err))
    end

    local by_instance = {}
    for i, v in ipairs(vecs) do
        local name = owners[i]
        if name then
            by_instance[name] = by_instance[name] or {}
            core.table.insert(by_instance[name], semantic.normalize(v))
        end
    end
    return by_instance
end


-- Guaranteed fallback: catchall instance if configured, else the first
-- instance. Never fails, so a request always has a target.
local function semantic_fallback(conf)
    for _, inst in ipairs(conf.instances) do
        if inst.catchall then
            return inst.name, inst
        end
    end
    local inst = conf.instances[1]
    return inst.name, inst
end


local function pick_semantic_instance(ctx, conf)
    local version = plugin.conf_version(conf)
    local ok, by_instance = pcall(lrucache_semantic_vectors,
                                  ctx.matched_route.key .. "#semantic", version,
                                  build_instance_vectors, conf)
    if not ok or not by_instance then
        core.log.warn("semantic routing: ", by_instance, ", falling back")
        return semantic_fallback(conf)
    end

    local prompt = extract_last_user_message()
    if not prompt then
        core.log.warn("semantic routing: no user message found, falling back")
        return semantic_fallback(conf)
    end

    -- pcall, like the reference path above: the embedding response is
    -- provider-controlled, so a raise here must fall back rather than 500.
    if #prompt > MAX_EMBED_PROMPT_BYTES then
        prompt = sub(prompt, 1, MAX_EMBED_PROMPT_BYTES)
    end

    -- pcall, like the reference path above: the embedding response is
    -- provider-controlled, so a raise here must fall back rather than 500.
    local fetched, qvecs, err = pcall(embedding.fetch, conf.embeddings, { prompt })
    if not fetched then
        core.log.warn("semantic routing: query embedding error: ", qvecs, ", falling back")
        return semantic_fallback(conf)
    end
    if not qvecs or not qvecs[1] then
        core.log.warn("semantic routing: query embedding failed: ", err, ", falling back")
        return semantic_fallback(conf)
    end
    local qvec = semantic.normalize(qvecs[1])
    local qdim = #qvec

    local ranked = {}
    for _, inst in ipairs(conf.instances) do
        local refs = by_instance[inst.name]
        if refs then
            local scores = {}
            for _, rv in ipairs(refs) do
                -- guard against dimension drift (e.g. embedding model changed):
                -- mismatched vectors would make dot() error, so fail open instead.
                if #rv ~= qdim then
                    core.log.warn("semantic routing: embedding dimension mismatch ",
                                  "(query ", qdim, " vs reference ", #rv, "), falling back")
                    return semantic_fallback(conf)
                end
                scores[#scores + 1] = semantic.dot(qvec, rv)
            end
            core.table.insert(ranked, {
                name = inst.name,
                score = semantic.max(scores),
            })
        end
    end
    core.table.sort(ranked, function(a, b) return a.score > b.score end)

    local expose_scores = conf.balancer.expose_scores
    if expose_scores then
        local parts = {}
        for _, c in ipairs(ranked) do
            parts[#parts + 1] = c.name .. ":" .. string.format("%.4f", c.score)
        end
        core.response.set_header("X-AI-Semantic-Scores", table_concat(parts, ","))
    end

    -- Highest score first; pick the first instance that clears its own threshold
    -- (per-instance override, else the global balancer.threshold).
    for _, cand in ipairs(ranked) do
        local inst = get_instance_conf(conf.instances, cand.name)
        local thr = inst.threshold or conf.balancer.threshold or 0
        if cand.score >= thr then
            if expose_scores then
                core.response.set_header("X-AI-Semantic-Route", cand.name)
            end
            core.log.info("semantic routing picked instance: ", cand.name,
                          ", score: ", cand.score)
            return cand.name, inst
        end
    end

    if expose_scores then
        core.response.set_header("X-AI-Semantic-Route", "fallback")
    end
    -- Only on the fallback path: surface why nothing matched, without requiring
    -- expose_scores. Cheap, because this runs once per unmatched request.
    local unmatched = {}
    for _, c in ipairs(ranked) do
        unmatched[#unmatched + 1] = c.name .. ":" .. string.format("%.4f", c.score)
    end
    core.log.warn("semantic routing: no instance cleared threshold (scores: ",
                  table_concat(unmatched, ","), "), falling back")
    return semantic_fallback(conf)
end


local function pick_ai_instance(ctx, conf, ups_tab)
    local instance_name, instance_conf, err
    if conf.balancer and conf.balancer.algorithm == "semantic" then
        instance_name, instance_conf = pick_semantic_instance(ctx, conf)
    elseif #conf.instances == 1 then
        instance_name = conf.instances[1].name
        instance_conf = conf.instances[1]
    else
        instance_name, instance_conf, err = pick_target(ctx, conf, ups_tab)
    end

    core.log.info("picked instance: ", instance_name)
    return instance_name, instance_conf, err
end

function _M.access(conf, ctx)
    -- Detect the client protocol and read the body first. get_json_request_body_table
    -- reads and size-checks the body exactly once (bounded by max_req_body_size,
    -- rejecting via Content-Length before buffering), so oversized requests are
    -- rejected before any balancer / DNS / health-check work below.
    local err, code = base.detect_request_type(ctx, conf.max_req_body_size)
    if err then
        return code or 400, err
    end

    local ups_tab = {}
    local algo = core.table.try_read_attr(conf, "balancer", "algorithm")
    if algo == "chash" then
        local hash_on = core.table.try_read_attr(conf, "balancer", "hash_on")
        local hash_key = core.table.try_read_attr(conf, "balancer", "key")
        ups_tab["key"] = hash_key
        ups_tab["hash_on"] = hash_on
    end

    local name, ai_instance, perr = pick_ai_instance(ctx, conf, ups_tab)
    if perr then
        return 503, perr
    end
    ctx.picked_ai_instance_name = name
    ctx.picked_ai_instance = ai_instance
    ctx.balancer_ip = name
    ctx.bypass_nginx_upstream = true
end


local function retry_on_error(ctx, conf, code, body)
    if not ctx.server_picker then
        return code
    end
    ctx.server_picker.after_balance(ctx, true)
    if (code == 429 and fallback_strategy_has(conf.fallback_strategy, "http_429")) or
       (code >= 500 and code < 600 and
       fallback_strategy_has(conf.fallback_strategy, "http_5xx")) then
        -- Slow-failure guard: only retry when the failed attempt finished within
        -- retry_on_failure_within_ms. A slow failure (e.g. a 5xx returned after
        -- minutes) is given back to the client directly, so fallback never doubles
        -- the client's wait time. ctx.llm_request_start_time is reset by base
        -- before_proxy at the start of every attempt, so this measures the elapsed
        -- time of the attempt that just failed.
        if conf.retry_on_failure_within_ms and ctx.llm_request_start_time then
            local elapsed_ms = (ngx_now() - ctx.llm_request_start_time) * 1000
            if elapsed_ms > conf.retry_on_failure_within_ms then
                core.log.warn("ai instance failed after ", elapsed_ms,
                              "ms, exceeding retry_on_failure_within_ms ",
                              conf.retry_on_failure_within_ms, ", not retrying")
                return code
            end
        end

        -- Cap the number of fallback retries so a single request does not exhaust
        -- every instance when many are configured.
        if conf.max_retries then
            ctx.ai_retries = (ctx.ai_retries or 0) + 1
            if ctx.ai_retries > conf.max_retries then
                core.log.warn("reached max_retries ", conf.max_retries,
                              ", not retrying")
                return code
            end
        end

        local failed_instance = ctx.picked_ai_instance_name
        local name, ai_instance, err = pick_ai_instance(ctx, conf)
        if err then
            core.log.error("failed to pick new AI instance: ", err)
            return 502
        end
        -- The failed attempt's body never reaches the client (a later attempt
        -- responds instead), so surface the upstream error here for diagnostics.
        core.log.warn("ai instance ", failed_instance, " returned status ", code,
                      ", falling back to ", name, ". upstream error body: ",
                      body or "")
        ctx.balancer_ip = name
        ctx.picked_ai_instance_name = name
        ctx.picked_ai_instance = ai_instance
        return
    end
    return code
end

function _M.construct_upstream(instance)
    if not instance then
        return nil, "instance configuration is nil"
    end
    local upstream = {}
    local nodes = instance._dns_nodes
    if not nodes then
        resolve_endpoint(instance)
        nodes = instance._dns_nodes
        if not nodes then
            return nil, "failed to resolve endpoint for instance: " .. instance.name
        end
    end

    local upstream_nodes = core.table.new(#nodes, 0)
    for _, node in ipairs(nodes) do
        if not node.host or not node.port then
            return nil, "invalid upstream node: missing host or port"
        end

        core.table.insert(upstream_nodes, {
            host = node.host,
            port = node.port,
            weight = 1,
            priority = 0,
            domain = node.domain,
        })
    end

    local checks = instance.checks
    local auth = instance.auth or {}
    if checks and checks.active then
        -- Clone checks to avoid in-place mutation across requests
        checks = core.table.deepcopy(checks)
        if auth.header then
            local add_headers = {}
            checks.active.req_headers = checks.active.req_headers or {}
            for _, v in ipairs(checks.active.req_headers) do
                add_headers[v] = true
            end
            for k, v in pairs(auth.header) do
                local header = string.format("%s: %s", k, v)
                if not add_headers[header] then
                    core.table.insert(checks.active.req_headers, header)
                end
            end
        end
        if auth.query then
            local http_path = checks.active.http_path or "/"
            local sep = string.find(http_path, "?", 1, true) and "&" or "?"
            checks.active.http_path = http_path .. sep ..
                                      core.string.encode_args(auth.query)
        end
    end
    upstream.nodes = upstream_nodes
    upstream.checks = checks
    upstream._nodes_ver = instance._nodes_ver
    return upstream
end


function _M.before_proxy(conf, ctx)
     return base.before_proxy(conf, ctx, function (ctx, conf, code, body)
        return retry_on_error(ctx, conf, code, body)
    end)
end

function _M.log(conf, ctx)
    if ctx.llm_active_connections_tracked then
        exporter.dec_llm_active_connections(ctx)
        ctx.llm_active_connections_tracked = false
    end
    if conf.logging then
        base.set_logging(ctx, conf.logging.summaries, conf.logging.payloads)
    end
end

return _M
