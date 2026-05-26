local require = require
local apisix = require("apisix")
local core = require("apisix.core")
local uuid = require("resty.jit-uuid")

local conf_path = "apisix.plugins.toolset.config"

local ngx = ngx
local pairs = pairs
local type = type
local package = package
local tostring = tostring
local format = string.format
local floor = math.floor
local gsub = ngx.re.gsub
local m_random = math.random
local m_randomseed = math.randomseed
local t_remove = table.remove
local re_match = ngx.re.match
local counter = 1

local old_http_access_phase
local old_match_route
local old_http_log_phase
local old_http_balancer_phase
local old_http_header_filter_phase
local old_http_body_filter_phase
local old_resolve

local schema = {}

local PHASE_UPSTREAM = "upstream (req + response)"
local PHASE_CLIENT = "response"

local suffix = [[
+----------+---------------------------+----------+-------------------------+
]]
local prefix = [[

+----------+---------------------------+----------+-------------------------+
| Role     | Phase                     | Timespan | Start time              |
]] .. suffix

local trace_headers = {
  "x-request-id", -- request id header
  "sw8",          -- skywalking
  "traceparent",  -- opentelemetry
  "x-b3-traceid", -- zipkin
}
local plugin_name = "trace"

local _M = {
  version = 0.1,
  priority = 22901,
  name = plugin_name,
  schema = schema,
  scope = "global",
}

local function nspaces(n)
  return (" "):rep(n)
end

local function add_entry(phase, timespan, curtime)
  core.log.info("add entry for: ", phase)
  local role
  local tpl = [[
| %s| %s| %s| %s |
]]
  if phase == PHASE_UPSTREAM then
    role = "Upstream "
  elseif phase == PHASE_CLIENT then
    role = "Client   "
  else
    role = "APISIX   "
  end

  -- add spaces around the text for table formatting
  phase = phase .. nspaces(26 - #phase)
  timespan = timespan .. nspaces(9 - #tostring(timespan))
  ngx.ctx.trace_log = ngx.ctx.trace_log .. format(tpl, role, phase, timespan, curtime)
end


local function timespan(raw)
  if raw == 0 then
    return "0ms"
  end
  local factor = 1000 -- 1000ms in 1s
  local unit = "ms"
  if raw >= 1 then  -- if greater than 1s don't convert to ms
    factor = 1
    unit = "s"
  end
  return floor(raw * factor + 0.5) .. unit
end


local function localtime_msec(now)
  local lt = ngx.localtime()
  local msec = now * 1000 - floor(now) * 1000
  if msec > 0 then
    return lt .. "." .. msec
  end
  return lt .. ".000"
end


local function match(incoming, conf)
  conf = gsub(conf, "\\*", ".*")
  conf = "^" .. conf .. "$"
  core.log.info("matching: ", incoming, " against: ", conf)

  local matches = re_match(incoming, "^" .. conf .. "$", "jo")
  if not matches then
    return nil
  end
  return matches[0]
end


local unique_random
do
  local numbers = {}
  for i = 1, 100 do
    numbers[i] = i
  end
  unique_random = function()
    m_randomseed(ngx.now())
    while true do
      local index = m_random(100)
      local num = numbers[index]
      if num then
        t_remove(numbers, index)
        return num
      end
    end
  end
end


local function incr_counter()
  counter = counter + 1
  if counter > 99 then
    counter = 0
  end
end


local function preprocess(trace_conf, ctx)
  if not trace_conf.rate or type(trace_conf.rate) ~= "number" then
    ctx.trace = true -- trace all reqs if rate isn't defined
    return
  end
  if trace_conf.rate == 1 then
    ctx.trace = counter == 1 -- trace only first request
    incr_counter()
    return
  end
  core.log.info("trace_conf.rate: ", trace_conf.rate)
  local rand = unique_random()
  if rand <= trace_conf.rate then
    ctx.trace = true
  end
  core.log.info("random number: ", rand)
  incr_counter()
end


local function check(trace_conf, uri_or_host)
  for _, val in pairs(trace_conf) do
    if match(uri_or_host, val) == uri_or_host then
      return true
    end
  end
  return false
end


local function check_host(trace_conf)
  local req_host = core.request.header(ngx.ctx, "host")
  if (trace_conf.hosts and #trace_conf.hosts > 0) and (req_host and #req_host > 0) then
    return check(trace_conf.hosts, req_host)
  end
  -- pass host check if hosts field is not defined in config.lua
  return trace_conf.hosts ~= nil
end


local function check_uri(trace_conf)
  if trace_conf.paths and #trace_conf.paths > 0 then
    return check(trace_conf.paths, ngx.ctx.api_ctx.var.request_uri)
  end
  -- pass uri check if paths field is not defined in config.lua
  return true
end


local function prepend(ctx, field, val)
  ctx.trace_log = "\n" .. field .. ": " .. val .. ctx.trace_log
end


local function add_headers(ctx)
  local count = 0
  for _, header_field in pairs(trace_headers) do
    local val = core.request.header(ctx, header_field)
    if val and #val > 0 then
      prepend(ctx, header_field, val)
      count = count + 1
    end
  end
  return count
end


local function add_vars(ctx, vars)
  local count = 0
  if vars and #vars > 0 then
    for _, var in pairs(vars) do
      local val = ngx.var[var]
      if val and #val > 0 then
        prepend(ctx, var, val)
        count = count + 1
      end
    end
  end
  return count
end


function _M.init()
  package.loaded[conf_path] = false
  local trace_conf = require(conf_path).trace
  core.log.info("trace_conf: ", core.json.encode(trace_conf))

  local conf = core.config.local_conf()
  local router_name = "radixtree_uri"
  if conf and conf.apisix and conf.apisix.router then
    router_name = conf.apisix.router.http or router_name
  end

  local dns = require("apisix.core.dns.client")
  if dns then
    if not old_resolve then
      old_resolve = dns.resolve
    end

    dns.resolve = function (...)
      local match_start = ngx.now()
      ngx.ctx.dns_lt = localtime_msec(match_start)
      local ret = old_resolve(...)
      ngx.update_time()

      ngx.ctx.dns_resolve_timespan = ngx.now() - match_start
      return ret
    end
  end

  local router = require("apisix.http.router." .. router_name)
  if not old_match_route then
    old_match_route = router.match
  end
  router.match = function(...)
    local match_start = ngx.now()
    ngx.ctx.match_lt = localtime_msec(match_start)

    old_match_route(...)
    ngx.update_time()

    ngx.ctx.match_timespan = ngx.now() - match_start
  end

  if not old_http_access_phase then
    old_http_access_phase = apisix.http_access_phase
  end
  apisix.http_access_phase = function(...)
    ngx.ctx.trace = false
    preprocess(trace_conf, ngx.ctx)
    if not ngx.ctx.trace then
      old_http_access_phase(...)
    else
      ngx.ctx.trace_log = prefix

      local access_start = ngx.now()
      ngx.ctx.req_start = access_start
      ngx.ctx.access_lt = localtime_msec(access_start)

      old_http_access_phase(...)

      local host_pass = check_host(trace_conf)
      local path_pass = check_uri(trace_conf)

      core.log.info("path check: ", path_pass, ". host check: ", host_pass)
      ngx.ctx.trace = path_pass or host_pass
      ngx.update_time()

      ngx.ctx.access_timespan = ngx.now() - access_start
    end
  end

  if not old_http_balancer_phase then
    old_http_balancer_phase = apisix.http_balancer_phase
  end
  apisix.http_balancer_phase = function(...)
    if not ngx.ctx.trace then
      old_http_balancer_phase(...)
    else
      local num_headers = add_headers(ngx.ctx)
      local num_vars = add_vars(ngx.ctx, trace_conf.vars)
      -- if no vars or headers were added add a uuid
      if (num_headers + num_vars) < 1 and trace_conf.gen_uid then
        ngx.ctx.trace_log = "\n" .. "uuid: " .. uuid() .. ngx.ctx.trace_log
      end

      local balancer_start = ngx.now()
      ngx.ctx.balancer_lt = localtime_msec(balancer_start)

      old_http_balancer_phase(...)
      ngx.update_time()

      ngx.ctx.balancer_timespan = ngx.now() - balancer_start
      ngx.update_time()
      ngx.ctx.upstream_start = ngx.now()
      ngx.ctx.upstream_lt = localtime_msec(ngx.ctx.upstream_start)
    end
  end

  if not old_http_header_filter_phase then
    old_http_header_filter_phase = apisix.http_header_filter_phase
  end
  apisix.http_header_filter_phase = function(...)
    if not ngx.ctx.trace then
      old_http_header_filter_phase(...)
    else
      local header_filter_start = ngx.now()
      ngx.ctx.upstream_end = header_filter_start
      ngx.ctx.header_filter_start = localtime_msec(header_filter_start)

      old_http_header_filter_phase(...)
      ngx.update_time()

      ngx.ctx.header_filter_timespan = ngx.now() - header_filter_start
    end
  end

  if not old_http_body_filter_phase then
    old_http_body_filter_phase = apisix.http_body_filter_phase
  end
  apisix.http_body_filter_phase = function(...)
    local body_filter_start = ngx.now()
    if not ngx.ctx.trace then
      old_http_body_filter_phase(...)
    else
      if not ngx.ctx.bf_timespan then
        ngx.ctx.bf_timespan = 0
        ngx.ctx.bf_lt = localtime_msec(body_filter_start)
      end

      old_http_body_filter_phase(...)
      ngx.update_time()

      ngx.ctx.bf_end = ngx.now()
      ngx.ctx.bf_timespan = ngx.ctx.bf_timespan + (ngx.ctx.bf_end - body_filter_start)
      ngx.ctx.response_lt = localtime_msec(ngx.ctx.bf_end)
    end
  end

  if not old_http_log_phase then
    old_http_log_phase = apisix.http_log_phase
  end
  apisix.http_log_phase = function(...)
    if not ngx.ctx.trace then
      old_http_log_phase(...)
    else
      local log_start = ngx.now()
      local log_lt = localtime_msec(log_start)

      old_http_log_phase(...)
      ngx.update_time()
      local log_end = ngx.now()

      local premature = false
      -- when route match fails access_timespan = nil
      if not ngx.ctx.access_timespan then
        ngx.ctx.access_timespan = 0
        ngx.ctx.balancer_timespan = 0
        premature = true
      end

      local upstream_timespan = 0
      if not premature then
        upstream_timespan = ngx.ctx.upstream_end - ngx.ctx.upstream_start
      end

      local client_timespan = log_start - ngx.ctx.bf_end
      local log_timespan = log_end - log_start
      local total_time = ngx.ctx.access_timespan + ngx.ctx.balancer_timespan + upstream_timespan +
                         ngx.ctx.header_filter_timespan + ngx.ctx.bf_timespan + client_timespan +
                         log_timespan

      if total_time >= (trace_conf.timespan_threshold or 0)  then
        add_entry("access", timespan(ngx.ctx.access_timespan), ngx.ctx.access_lt)
        add_entry("\\_match_route", timespan(ngx.ctx.match_timespan), ngx.ctx.match_lt)
        if ngx.ctx.dns_resolve_timespan then
          add_entry("\\_dns_resolve", timespan(ngx.ctx.dns_resolve_timespan), ngx.ctx.dns_lt)
        end
        if not premature then
          add_entry("balancer", timespan(ngx.ctx.balancer_timespan), ngx.ctx.balancer_lt)
          add_entry(PHASE_UPSTREAM,
            timespan(upstream_timespan), ngx.ctx.upstream_lt)
        end
        add_entry("header_filter", timespan(ngx.ctx.header_filter_timespan),
                  ngx.ctx.header_filter_start)
        add_entry("body_filter", timespan(ngx.ctx.bf_timespan), ngx.ctx.bf_lt)
        if not premature then
          add_entry(PHASE_CLIENT, timespan(client_timespan), ngx.ctx.response_lt)
        end
        add_entry("log", timespan(log_timespan), log_lt)
        core.log.warn("trace: ", ngx.ctx.trace_log .. suffix)
      end
    end
    ngx.ctx.trace_log = ""    -- clear trace
    ngx.ctx.bf_timespan = nil -- clear body_filter timespan
  end
end

function _M.destroy()
  local conf = core.config.local_conf()
  local router_name = "radixtree_uri"
  if conf and conf.apisix and conf.apisix.router then
    router_name = conf.apisix.router.http or router_name
  end

  local router = require("apisix.http.router." .. router_name)
  router.match = old_match_route

  apisix.http_access_phase = old_http_access_phase
  apisix.http_balancer_phase = old_http_balancer_phase
  apisix.http_header_filter_phase = old_http_header_filter_phase
  apisix.http_body_filter_phase = old_http_body_filter_phase
  apisix.http_log_phase = old_http_log_phase
end

return _M
