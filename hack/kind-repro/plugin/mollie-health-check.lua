local core = require('apisix.core')
local http = require('resty.http')
local ngx = ngx

local plugin_name = 'mollie-health-check'

-- Gates the readiness probe on plugin-load health so a stale image missing a plugin
-- fails readiness instead of silently serving degraded traffic. Design and operational
-- details: docs/guides-and-runbooks/readiness-plugin-load-gating.md (PS-11555).

-- APISIX Control API endpoint that lists the plugins APISIX actually registered.
-- It is backed by apisix.plugin.get_all(), so a plugin that failed to load is
-- absent here. Localhost-only; requires `enable_control: true` in config.yaml.
local control_schema_url = "http://127.0.0.1:9090/v1/schema"

-- Worker-level cache of the readiness verdict:
--   false = not yet confirmed (re-checked on each readiness probe)
--   true  = every configured plugin is loaded (latched: the plugin set is fixed
--           for the pod's lifetime in standalone mode, so we never re-query after
--           a success and steady-state probes do zero HTTP).
-- A failure is deliberately NOT latched, so a transient Control API error during
-- early startup self-heals on the next probe.
local plugins_verified = false

-- Cold-start readiness gate (PS-12691): a freshly created health-check target
-- defaults to "healthy" with zero probes (resty.healthcheck's add_target), so
-- a pod that restarts while its backend is already unhealthy briefly routes
-- real traffic to it -- until the first active probe corrects the target's
-- state. Blocks readiness until every configured critical upstream has had
-- at least one real active-check attempt. Worker-scoped: `ensured_once` so
-- ensure_checker is only called once per worker (its underlying waiting_pool
-- is per-worker state), `gate_started_at` to bound how long an unresolvable
-- critical upstream (typo'd id, checker never created) can block readiness --
-- a plain in-Lua timestamp, not the drain-marker gate's procfs-based
-- container-start helper, since this only needs "how long has this worker
-- been evaluating the gate," not a cross-container file-vs-start comparison,
-- and its safe-fallback direction is the opposite of the drain marker's
-- (fail toward not-ready, not toward ready, until the bound is hit).
local ensured_once = false
local gate_started_at = ngx.time()

local schema = {
    type = "object",
    properties = {
        maintenance_file = {type = "string", default = "/tmp/maintenance_mode_enabled"},
        normal_status = {type = "integer", default = ngx.HTTP_OK, minimum = 100, maximum = 599},
        normal_response_message = {type = "string", default = "ok"},
        maintenance_status = {type = "integer", default = ngx.HTTP_SERVICE_UNAVAILABLE, minimum = 100, maximum = 599},
        maintenance_response_message = {type = "string", default = "not_ok"},
        ready_uri = {type = "string", default = "/health_check_internal/ready"},
        live_uri = {type = "string", default = "/health_check_internal/live"},
        critical_upstreams = {
            type = "array",
            items = {type = "string"},
            default = {},
            description = "Upstream ids (as configured under apisixUpstreams) that must have "
                .. "completed at least one active health-check probe before this pod reports ready.",
        },
        critical_upstreams_max_wait = {
            type = "integer",
            default = 15,
            minimum = 0,
            description = "Seconds after which an unprobed critical upstream stops blocking "
                .. "readiness (fail-open, logged loudly) -- guards a typo'd id or a checker "
                .. "that never gets created.",
        },
    },
}

local _M = {
    version = 0.1,
    priority = 1000,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf, _schema_type)
    return core.schema.check(schema, conf)
end

-- Returns true only if every plugin listed in config.yaml `plugins:` is present
-- in APISIX's loaded set (per the Control API). Fail-closed: any error or any
-- missing plugin returns false so the readiness probe fails and the pod is held
-- out of rotation instead of silently serving 404s for the dropped routes.
local function all_plugins_loaded()
    if plugins_verified then
        return true
    end

    local ok_conf, config_local = pcall(require, "apisix.core.config_local")
    if not ok_conf then
        core.log.error("health-check: cannot load apisix.core.config_local: ", config_local)
        return false
    end

    local local_conf = config_local.local_conf()
    -- `plugins` must be a non-empty array. A missing/empty/non-array value is
    -- anomalous: the config wasn't loaded as expected. It can never legitimately
    -- be empty here — this very health-check plugin runs from that same list, so
    -- at minimum it must be present. Fail closed rather than treating it as
    -- "nothing to verify" (the type guard also avoids `#` erroring on a non-table).
    if not local_conf or type(local_conf.plugins) ~= "table" or #local_conf.plugins == 0 then
        core.log.error("health-check: no plugins in local config; failing closed")
        return false
    end

    local configured = local_conf.plugins

    local httpc = http.new()
    -- Keep the worst case (connect+send+read) comfortably under the kubelet probe
    -- timeout (timeoutSeconds: 1): 3x200ms = 600ms leaves ~400ms of margin for GC
    -- pauses/load. The Control API is localhost so 200ms per phase is ample.
    httpc:set_timeouts(200, 200, 200)
    local res, err = httpc:request_uri(control_schema_url, {method = "GET"})
    if not res then
        -- A connection refused here usually means the Control API is not enabled
        -- (enable_control) — readiness fails closed until it is reachable.
        core.log.error("health-check: Control API request failed (is enable_control set?): ", err)
        return false
    end
    if res.status ~= 200 then
        core.log.error("health-check: Control API returned status ", res.status)
        return false
    end

    local body, decode_err = core.json.decode(res.body)
    if not body then
        core.log.error("health-check: failed to decode Control API /v1/schema: ", decode_err)
        return false
    end
    if type(body.plugins) ~= "table" then
        core.log.error("health-check: unexpected Control API /v1/schema response (no plugins map)")
        return false
    end
    local loaded = body.plugins

    local missing = {}
    for _, name in ipairs(configured) do
        if loaded[name] == nil then
            missing[#missing + 1] = name
        end
    end

    if #missing > 0 then
        core.log.error("health-check: configured plugins not loaded: ", table.concat(missing, ", "))
        return false
    end

    plugins_verified = true
    return true
end

-- Returns true once every id in conf.critical_upstreams has had at least one
-- real active-check attempt (resty.healthcheck's all_targets_probed --
-- attempted, not "healthy"), or once conf.critical_upstreams_max_wait has
-- elapsed since this worker started evaluating the gate, whichever comes
-- first. No configured critical upstreams is trivially true (opt-in gate).
--
-- ensure_checker is called at most once per worker: checker creation is
-- otherwise entirely lazy (only ever triggered by live request traffic), so
-- a critical-but-currently-idle upstream on a fresh pod would never get a
-- checker built at all without this -- this forces that seeding regardless
-- of whether the upstream has served any traffic yet.
local function critical_upstreams_probed(conf)
    local ids = conf.critical_upstreams
    if not ids or #ids == 0 then
        return true
    end

    local ok_hcm, healthcheck_manager = pcall(require, "apisix.healthcheck_manager")
    if not ok_hcm then
        core.log.error("health-check: cannot load apisix.healthcheck_manager: ", healthcheck_manager)
        return false
    end

    if not ensured_once then
        for _, id in ipairs(ids) do
            local ok, err = healthcheck_manager.ensure_checker("/upstreams/" .. id)
            if not ok then
                core.log.warn("health-check: ensure_checker failed for critical upstream '",
                              id, "': ", err)
            end
        end
        ensured_once = true
    end

    local unprobed = {}
    for _, id in ipairs(ids) do
        if not healthcheck_manager.is_resource_probed("/upstreams/" .. id) then
            unprobed[#unprobed + 1] = id
        end
    end

    if #unprobed == 0 then
        return true
    end

    local elapsed = ngx.time() - gate_started_at
    if elapsed >= (conf.critical_upstreams_max_wait or 15) then
        core.log.error("health-check: failing open after ", elapsed,
                       "s -- critical upstream(s) never probed: ",
                       table.concat(unprobed, ", "),
                       " (misconfigured id, or checker never created -- investigate)")
        return true
    end

    core.log.warn("health-check: not ready, critical upstream(s) unprobed: ",
                  table.concat(unprobed, ", "), " (", elapsed, "s elapsed)")
    return false
end

function _M.rewrite(conf, _ctx)
    local uri = ngx.var.uri or ""

    -- Liveness must reflect "process is alive" only, never plugin-load state, so
    -- the kubelet can distinguish liveness from readiness. Keep it independent.
    if uri == conf.live_uri then
        return core.response.exit(conf.normal_status, conf.normal_response_message)
    end

    if uri == conf.ready_uri then
        if not all_plugins_loaded() then
            ngx.header["X-APISIX-Route"] = "health-check-plugin-failure"
            return core.response.exit(ngx.HTTP_SERVICE_UNAVAILABLE,
                {status = 503, detail = "Plugin load failure - pod not ready"})
        end

        if not critical_upstreams_probed(conf) then
            ngx.header["X-APISIX-Route"] = "health-check-upstream-unprobed"
            return core.response.exit(ngx.HTTP_SERVICE_UNAVAILABLE,
                {status = 503, detail = "Critical upstream health check not yet probed - pod not ready"})
        end

        local f = io.open(conf.maintenance_file, "r")
        if f ~= nil then
            f:close()
            return core.response.exit(conf.maintenance_status, conf.maintenance_response_message)
        end
        return core.response.exit(conf.normal_status, conf.normal_response_message)
    end

    return core.response.exit(ngx.HTTP_NOT_FOUND, "Not found")
end

return _M
