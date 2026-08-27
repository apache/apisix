--------------------------------------------------------------------------
-- Healthcheck library for OpenResty.
--
-- Some notes on the usage of this library:
--
-- - Each target will have 4 counters, 1 success counter and 3 failure
-- counters ('http', 'tcp', and 'timeout'). Any failure will _only_ reset the
-- success counter, but a success will reset _all three_ failure counters.
--
-- - All targets are uniquely identified by their IP address and port number
-- combination, most functions take those as arguments.
--
-- - All keys in the SHM will be namespaced by the healthchecker name as
-- provided to the `new` function. Hence no collissions will occur on shm-keys
-- as long as the `name` is unique.
--
-- - Active healthchecks will be synchronized across workers, such that only
-- a single active healthcheck runs.
--
-- - Events will be raised in every worker, see [lua-resty-worker-events](https://github.com/Kong/lua-resty-worker-events)
-- for details.
--
-- @copyright 2017-2023 Kong Inc.
-- @author Hisham Muhammad, Thijs Schreijer
-- @license Apache 2.0

local ERR = ngx.ERR
local WARN = ngx.WARN
local DEBUG = ngx.DEBUG
local ngx_log = ngx.log
local tostring = tostring
local ipairs = ipairs
local table_insert = table.insert
local table_remove = table.remove
local string_format = string.format
local ssl = require("ngx.ssl")
local resty_timer = require "resty.timer"
local bit = require("bit")
local re_find = ngx.re.find
local ngx_now = ngx.now
local ngx_worker_id = ngx.worker.id
local ngx_worker_pid = ngx.worker.pid
local pcall = pcall
local get_phase = ngx.get_phase
local type = type
local assert = assert


local RESTY_EVENTS_VER = [[^0\.1\.\d+$]]
local RESTY_WORKER_EVENTS_VER = "0.3.3"


local new_tab
local nkeys
local is_array
local codec


local TESTING = _G.__TESTING_HEALTHCHECKER or false

do
  local ok

  ok, new_tab = pcall(require, "table.new")
  if not ok then
    new_tab = function () return {} end
  end

  -- OpenResty branch of LuaJIT New API
  ok, nkeys = pcall(require, "table.nkeys")
  if not ok then
    nkeys = function (tab)
      local count = 0
      for _, v in pairs(tab) do
        if v ~= nil then
          count = count + 1
        end
      end
      return count
    end
  end

  ok, is_array = pcall(require, "table.isarray")
  if not ok then
    is_array = function(t)
      for k in pairs(t) do
          if type(k) ~= "number" or math.floor(k) ~= k then
            return false
          end
      end
      return true
    end
  end

  ok, codec = pcall(require, "string.buffer")
  if not ok then
      codec = require("cjson.safe").new()
  end
end


local worker_events
--- This function loads the worker events module received as arg. It will throw
-- error() if it is not possible to load the module.
local function load_events_module(self)
  if self.events_module == "resty.worker.events" then
    worker_events = require("resty.worker.events")
    assert(worker_events, "could not load lua-resty-worker-events")
    assert(worker_events._VERSION == RESTY_WORKER_EVENTS_VER,
          "unsupported lua-resty-worker-events version")

  elseif self.events_module == "resty.events" then
    worker_events = require("resty.events.compat")
    local version_match = ngx.re.match(worker_events._VERSION, RESTY_EVENTS_VER, "o")
    assert(version_match, "unsupported lua-resty-events version")

  else
    error("unknown events module")
  end

  assert(worker_events.configured(), "please configure the '" ..
          self.events_module .. "' module before using 'lua-resty-healthcheck'")
end


-- constants
local EVENT_SOURCE_PREFIX = "lua-resty-healthcheck"
local LOG_PREFIX = "[healthcheck] "
local SHM_PREFIX = "lua-resty-healthcheck:"
local EMPTY = setmetatable({},{
    __newindex = function()
      error("the EMPTY table is read only, check your code!", 2)
    end
  })

--- timer constants
-- evaluate active checks every 0.1s
local CHECK_INTERVAL = 0.1
-- use a 10% jitter to start each worker timer
local CHECK_JITTER = CHECK_INTERVAL * 0.1
-- lock valid period: the worker which acquires the lock owns it for 15 times
-- the check interval. If it does not update the shm during this period, we
-- consider that it is not able to continue checking (the worker probably was killed)
local LOCK_PERIOD = CHECK_INTERVAL * 15

-- Only the periodic-lock holder ever runs active probes (see active_check_timer
-- below), so every other worker's target.internal_health is updated *solely* by
-- the worker_events broadcast raised in incr_counter. That broadcast has no
-- delivery guarantee and, once a target is already at the reported health, is
-- never raised again for the same state -- so a single missed event permanently
-- strands a worker's local view (apache/apisix#13888). RECONCILE_INTERVAL bounds
-- how long that divergence can last: every worker re-derives internal_health
-- from the authoritative shm state on this cadence, independent of events.
local RECONCILE_INTERVAL = 1
-- interval between stale targets cleanup
local CLEANUP_INTERVAL = CHECK_INTERVAL * 25

-- Counters: a 32-bit shm integer can hold up to four 8-bit counters.
local CTR_SUCCESS = 0x00000001
local CTR_HTTP    = 0x00000100
local CTR_TCP     = 0x00010000
local CTR_TIMEOUT = 0x01000000

local MASK_FAILURE = 0xffffff00
local MASK_SUCCESS = 0x000000ff

local COUNTER_NAMES = {
  [CTR_SUCCESS] = "SUCCESS",
  [CTR_HTTP]    = "HTTP",
  [CTR_TCP]     = "TCP",
  [CTR_TIMEOUT] = "TIMEOUT",
}

--- The list of potential events generated.
-- The `checker.EVENT_SOURCE` field can be used to subscribe to the events, see the
-- example below. Each of the events will get a table passed containing
-- the target details `ip`, `port`, and `hostname`.
-- See [lua-resty-worker-events](https://github.com/Kong/lua-resty-worker-events).
-- @field remove Event raised when a target is removed from the checker.
-- @field healthy This event is raised when the target status changed to
-- healthy (and when a target is added as `healthy`).
-- @field unhealthy This event is raised when the target status changed to
-- unhealthy (and when a target is added as `unhealthy`).
-- @field mostly_healthy This event is raised when the target status is
-- still healthy but it started to receive "unhealthy" updates via active or
-- passive checks.
-- @field mostly_unhealthy This event is raised when the target status is
-- still unhealthy but it started to receive "healthy" updates via active or
-- passive checks.
-- @table checker.events
-- @usage -- Register for all events from `my_checker`
-- local event_callback = function(target, event, source, source_PID)
--   local t = target.ip .. ":" .. target.port .." by name '" ..
--             target.hostname .. "' ")
--
--   if event == my_checker.events.remove then
--     print(t .. "has been removed")
--   elseif event == my_checker.events.healthy then
--     print(t .. "is now healthy")
--   elseif event == my_checker.events.unhealthy then
--     print(t .. "is now unhealthy")
--   end
-- end
--
-- worker_events.register(event_callback, my_checker.EVENT_SOURCE)
local EVENTS = setmetatable({}, {
  __index = function(self, key)
    error(("'%s' is not a valid event name"):format(tostring(key)))
  end
})
for _, event in ipairs({
  "remove",
  "healthy",
  "unhealthy",
  "mostly_healthy",
  "mostly_unhealthy",
  "clear",
}) do
  EVENTS[event] = event
end

local INTERNAL_STATES = {}
for i, key in ipairs({
  "healthy",
  "unhealthy",
  "mostly_healthy",
  "mostly_unhealthy",
}) do
  INTERNAL_STATES[i] = key
  INTERNAL_STATES[key] = i
end

-- Some color for demo purposes
local use_color = false
local id = function(x) return x end
local worker_color = use_color and function(str) return ("\027["..tostring(31 + ngx_worker_pid() % 5).."m"..str.."\027[0m") end or id

-- Debug function
local function dump(...) print(require("pl.pretty").write({...})) end -- luacheck: ignore 211

local _M = {}

-- checker objects (weak) table
local hcs = setmetatable({}, {
  __mode = "v",
})

local active_check_timer

-- last time (ngx.now()) the shm-vs-local-cache reconciliation sweep ran; shared
-- by all checkers on this worker since the sweep itself iterates `hcs`
local last_reconcile_time = 0

-- serialize a table to a string
local serialize = codec.encode


-- deserialize a string to a table
local deserialize = codec.decode


local function key_for(key_prefix, ip, port, hostname)
  return string_format("%s:%s:%s%s", key_prefix, ip, port, hostname and ":" .. hostname or "")
end


-- resty.lock timeout when yieldable
local LOCK_TIMEOUT = 5

local run_locked
do
  -- resty_lock is restricted to this scope in order to keep sensitive
  -- lock-handling code separate separate from all other business logic
  --
  -- If you need to use resty_lock in a way that is not covered by the
  -- `run_locked` helper function defined below, it's strongly-advised to
  -- define it fully within this scope unless you have a very good reason
  --
  -- (see https://github.com/Kong/lua-resty-healthcheck/pull/112)
  local resty_lock = require "resty.lock"

  local yieldable = {
    rewrite = true,
    access  = true,
    content = true,
    timer   = true,
  }

  local function run_in_timer(premature, self, key, fn, ...)
    if premature then
      return
    end

    local ok, err = run_locked(self, key, fn, ...)
    if not ok then
      self:log(ERR, "locked function for key '", key, "' failed in timer: ", err)
    end
  end

  local function schedule(self, key, fn, ...)
    local ok, err = ngx.timer.at(0, run_in_timer, self, key, fn, ...)
    if not ok then
      return nil, "failed scheduling locked function for key '" .. key ..
                  "', " .. err
    end

    return "scheduled"
  end

  -- resty.lock consumes these options immediately, so this table can be reused
  local opts = {
    exptime = 10,           -- timeout after which lock is released anyway
    timeout = LOCK_TIMEOUT, -- max wait time to acquire lock
  }

  ---
  -- Acquire a lock and run a function
  --
  -- The function call itself is wrapped with `pcall` to protect against
  -- exception.
  --
  -- This function exhibits some special behavior when called during a
  -- non-yieldable phase such as `init_worker` or `log`:
  --
  -- 1. The lock timeout is set to 0 to ensure that `resty.lock` does not
  --    attempt to sleep/yield
  -- 2. If acquiring the lock fails due to a timeout, `run_locked`
  --    (this function) is re-scheduled to run in a timer. In this case,
  --    the function returns `"scheduled"`
  --
  -- @param self The checker object
  -- @param key the key/identifier to acquire a lock for
  -- @param fn The function to execute
  -- @param ... arguments that will be passed to fn
  -- @return The results of the function; or nil and an error message
  -- in case it fails locking.
  function run_locked(self, key, fn, ...)
    -- we're extra extra extra defensive in this code path
    local typ = type(key)
     -- XXX is a number key ever expected?
    assert(typ == "string" or typ == "number",
           "unexpected lock key type: " .. typ)
    key = tostring(key)

    -- first aqcuire a lock or conditionally re-schedule ourselves in a timer
    local lock
    do
      local yield = yieldable[get_phase()]

      if yield then
        opts.timeout = LOCK_TIMEOUT
      else
        -- if yielding is not possible in the current phase, use a zero timeout
        -- so that resty.lock will return `nil, "timeout"` immediately instead of
        -- calling ngx.sleep()
        opts.timeout = 0
      end

      local err
      lock, err = resty_lock:new(self.shm_name, opts)
      if not lock then
        return nil, "failed creating lock for '" .. key .. "', " .. err
      end

      local elapsed
      elapsed, err = lock:lock(key)

      if not elapsed and err == "timeout" and not yield then
        -- yielding is not possible in the current phase, so retry in a timer
        return schedule(self, key, fn, ...)

      elseif not elapsed then
        return nil, "failed acquiring lock for '" .. key .. "', " .. err
      end
    end

    local pok, perr, res = pcall(fn, ...)

    local ok, err = lock:unlock()
    if not ok then
      self:log(ERR, "failed unlocking '", key, "', ", err)
    end

    if not pok then
      return nil, "locked function threw an exception: " .. tostring(perr)
    end

    return perr, res
  end
end


local deepcopy
do
    local function _deepcopy(orig, copied)
        -- prevent infinite loop when a field refers its parent
        copied[orig] = true
        -- If the array-like table contains nil in the middle,
        -- the len might be smaller than the expected.
        -- But it doesn't affect the correctness.
        local len = #orig
        local copy = table.new(len, table.nkeys(orig) - len)
        for orig_key, orig_value in pairs(orig) do
            if type(orig_value) == "table" and not copied[orig_value] then
                copy[orig_key] = _deepcopy(orig_value, copied)
            else
                copy[orig_key] = orig_value
            end
        end

        local mt = getmetatable(orig)
        if mt ~= nil then
            setmetatable(copy, mt)
        end

        return copy
    end


    local copied_recorder = {}

    function deepcopy(orig)
        local orig_type = type(orig)
        if orig_type ~= 'table' then
            return orig
        end

        local res = _deepcopy(orig, copied_recorder)
        table.clear(copied_recorder)
        return res
    end
end


local checker = {}


------------------------------------------------------------------------------
-- Node management.
-- @section node-management
------------------------------------------------------------------------------


-- @return the target list from the shm, an empty table if not found, or
-- `nil + error` upon a failure
local function fetch_target_list(self)
  local target_list, err = self.shm:get(self.TARGET_LIST)
  if err then
    return nil, "failed to fetch target_list from shm: " .. err
  end

  return target_list and deserialize(target_list) or {}
end


local function with_target_list(self, fn)
  local targets, err = fetch_target_list(self)
  if not targets then
    return nil, err
  end

  -- this is only ever called in the context of `run_locked`,
  -- so no pcall needed
  return fn(targets)
end


--- Run the given function holding a lock on the target list.
-- @param self The checker object
-- @param fn The function to execute
-- @return The results of the function; or nil and an error message
-- in case it fails locking.
local function locking_target_list(self, fn)
  local ok, err = run_locked(self, self.TARGET_LIST_LOCK, with_target_list, self, fn)

  if ok == "scheduled" then
    self:log(DEBUG, "target_list function re-scheduled in timer")
  end

  return ok, err
end


--- Get a target
local function get_target(self, ip, port, hostname)
  hostname = hostname or ip
  return ((self.targets[ip] or EMPTY)[port] or EMPTY)[hostname]
end

--- Add a target to the healthchecker.
-- When the ip + port + hostname combination already exists, it will simply
-- return success (without updating `is_healthy` status).
-- @param ip IP address of the target to check.
-- @param port the port to check against.
-- @param hostname (optional) hostname to set as the host header in the HTTP
-- probe request
-- @param is_healthy (optional) a boolean value indicating the initial state,
-- default is `true`.
-- @param hostheader (optional) a value to use for the Host header on
-- active healthchecks.
-- @param tbl_meta (optional) a lua table with custom info of business stuff
-- @return `true` on success, or `nil + error` on failure.
function checker:add_target(ip, port, hostname, is_healthy, hostheader, tbl_meta)
  ip = tostring(assert(ip, "no ip address provided"))
  port = assert(tonumber(port), "no port number provided")
  hostname = hostname or ip
  if is_healthy == nil then
    is_healthy = true
  end

  local internal_health = is_healthy and "healthy" or "unhealthy"

  local ok, err = locking_target_list(self, function(target_list)
    local found = false

    -- check whether we already have this target
    for _, target in ipairs(target_list) do
      if target.ip == ip and target.port == port and target.hostname == (hostname) then
        if target.purge_time == nil then
          self:log(DEBUG, "adding an existing target: ", hostname or "", " ", ip,
                  ":", port, " (ignoring)")
          return false
        end
        target.purge_time = nil
        found = true
        internal_health = self:get_target_status(ip, port, hostname) and
                          "healthy" or "unhealthy"
        break
      end
    end

    -- we first add the internal health, and only then the updated list.
    -- this prevents a state where a target is in the list, but does not
    -- have a key in the shm.
    local ok, err = self.shm:set(key_for(self.TARGET_STATE, ip, port, hostname),
                                 INTERNAL_STATES[internal_health])
    if not ok then
      self:log(ERR, "failed to set initial health status in shm: ", err)
    end

    -- target does not exist, go add it
    if not found then
      target_list[#target_list + 1] = {
        ip = ip,
        port = port,
        hostname = hostname,
        hostheader = hostheader,
        meta = tbl_meta,
      }
    end
    target_list = serialize(target_list)

    ok, err = self.shm:set(self.TARGET_LIST, target_list)
    if not ok then
      return nil, "failed to store target_list in shm: " .. err
    end

    -- raise event for our newly added target
    if not found then
      self:raise_event(self.events[internal_health], ip, port, hostname)
    end

    return true
  end)

  if ok == false then
    -- the target already existed, no event, but still success
    return true
  end

  return ok, err

end


-- Remove health status entries from an individual target from shm
-- @param self The checker object
-- @param ip IP address of the target being checked.
-- @param port the port being checked against.
-- @param hostname hostname of the target being checked.
local function clear_target_data_from_shm(self, ip, port, hostname)
    local ok, err = self.shm:set(key_for(self.TARGET_STATE, ip, port, hostname), nil)
    if not ok then
      self:log(ERR, "failed to remove health status from shm: ", err)
    end
    ok, err = self.shm:set(key_for(self.TARGET_COUNTER, ip, port, hostname), nil)
    if not ok then
      self:log(ERR, "failed to clear health counter from shm: ", err)
    end
    ok, err = self.shm:set(key_for(self.TARGET_PROBED, ip, port, hostname), nil)
    if not ok then
      self:log(ERR, "failed to clear probe count from shm: ", err)
    end
end


--- Remove a target from the healthchecker.
-- The target not existing is not considered an error.
-- @param ip IP address of the target being checked.
-- @param port the port being checked against.
-- @param hostname (optional) hostname of the target being checked.
-- @return `true` on success, or `nil + error` on failure.
function checker:remove_target(ip, port, hostname)
  ip   = tostring(assert(ip, "no ip address provided"))
  port = assert(tonumber(port), "no port number provided")

  return locking_target_list(self, function(target_list)

    -- find the target
    local target_found
    for i, target in ipairs(target_list) do
      if target.ip == ip and target.port == port and target.hostname == hostname then
        target_found = target
        table_remove(target_list, i)
        break
      end
    end

    if not target_found then
      return true
    end

    -- go update the shm
    target_list = serialize(target_list)

    -- we first write the updated list, and only then remove the health
    -- status; this prevents race conditions when a healthchecker gets the
    -- initial state from the shm
    local ok, err = self.shm:set(self.TARGET_LIST, target_list)
    if not ok then
      return nil, "failed to store target_list in shm: " .. err
    end

    clear_target_data_from_shm(self, ip, port, hostname)

    -- raise event for our removed target
    self:raise_event(self.events.remove, ip, port, hostname)

    return true
  end)
end


--- Clear all healthcheck data.
-- @return `true` on success, or `nil + error` on failure.
function checker:clear()

  return locking_target_list(self, function(target_list)

    local old_target_list = target_list

    -- go update the shm
    target_list = serialize({})

    local ok, err = self.shm:set(self.TARGET_LIST, target_list)
    if not ok then
      return nil, "failed to store target_list in shm: " .. err
    end

    -- remove all individual statuses
    for _, target in ipairs(old_target_list) do
      local ip, port, hostname = target.ip, target.port, target.hostname
      clear_target_data_from_shm(self, ip, port, hostname)
    end

    self.targets = {}

    -- raise event for our removed target
    self:raise_event(self.events.clear)

    return true
  end)
end


--- Clear all healthcheck data after a period of time.
-- Useful for keeping target status between configuration reloads.
-- @param delay delay in seconds before purging target state.
-- @return `true` on success, or `nil + error` on failure.
function checker:delayed_clear(delay)
  assert(tonumber(delay), "no delay provided")

  return locking_target_list(self, function(target_list)
    local purge_time = ngx_now() + delay

    -- add purge time to all targets
    for _, target in ipairs(target_list) do
      target.purge_time = purge_time
    end

    target_list = serialize(target_list)
    local ok, err = self.shm:set(self.TARGET_LIST, target_list)
    if not ok then
      return nil, "failed to store target_list in shm: " .. err
    end

    return true
  end)
end


--- Get the current status of the target.
-- @param ip IP address of the target being checked.
-- @param port the port being checked against.
-- @param hostname the hostname of the target being checked.
-- @return `true` if healthy, `false` if unhealthy, or `nil + error` on failure.
function checker:get_target_status(ip, port, hostname)

  local target = get_target(self, ip, port, hostname)
  if not target then
    return nil, "target not found"
  end
  return target.internal_health == "healthy"
      or target.internal_health == "mostly_healthy"

end


------------------------------------------------------------------------------
-- Health management.
-- Functions that allow reporting of failures/successes for passive checks.
-- @section health-management
------------------------------------------------------------------------------


-- Run the given function holding a lock on the target.
-- @param self The checker object
-- @param ip Target IP
-- @param port Target port
-- @param hostname Target hostname
-- @param fn The function to execute
-- @return The results of the function; or true in case it fails locking and
-- will retry asynchronously; or nil+err in case it fails to retry.
local function locking_target(self, ip, port, hostname, fn)
  local key = key_for(self.TARGET_LOCK, ip, port, hostname)

  local ok, err = run_locked(self, key, fn)

  if ok == "scheduled" then
    self:log(DEBUG, "target function for ", key, " was re-scheduled")
  end

  return ok, err
end


-- Extract the value of the counter at `idx` from multi-counter `multictr`.
-- @param multictr A 32-bit multi-counter holding 4 values.
-- @param idx The shift index specifying which counter to get.
-- @return The 8-bit value extracted from the 32-bit multi-counter.
local function ctr_get(multictr, idx)
   return bit.band(multictr / idx, 0xff)
end


-- Increment the healthy or unhealthy counter. If the threshold of occurrences
-- is reached, it changes the status of the target in the shm and posts an
-- event.
-- @param self The checker object
-- @param health_report "healthy" for the success counter that drives a target
-- towards the healthy state; "unhealthy" for the failure counter.
-- @param ip Target IP
-- @param port Target port
-- @param hostname Target hostname
-- @param limit the limit after which target status is changed
-- @param ctr_type the counter to increment, see CTR_xxx constants
-- @return True if succeeded, or nil and an error message.
local function incr_counter(self, health_report, ip, port, hostname, limit, ctr_type)

  -- fail fast on counters that are disabled by configuration
  if limit == 0 then
    return true
  end

  hostname = hostname or ip
  port = tonumber(port)
  local target = get_target(self, ip, port, hostname)
  if not target then
    -- sync issue: warn, but return success
    self:log(WARN, "trying to increment a target that is not in the list: ",
    hostname and "(" .. hostname .. ") " or "", ip, ":", port)
    return true
  end

  local current_health = target.internal_health
  if health_report == current_health then
    -- No need to count successes when internal health is fully "healthy"
    -- or failures when internal health is fully "unhealthy"
    return true
  end

  return locking_target(self, ip, port, hostname, function()
    local counter_key = key_for(self.TARGET_COUNTER, ip, port, hostname)
    local multictr, err = self.shm:incr(counter_key, ctr_type, 0)
    if err then
      return nil, err
    end

    local ctr = ctr_get(multictr, ctr_type)

    self:log(WARN, health_report, " ", COUNTER_NAMES[ctr_type],
                   " increment (", ctr, "/", limit, ") for '", hostname or "",
                   "(", ip, ":", port, ")'")

    local new_multictr
    if ctr_type == CTR_SUCCESS then
      new_multictr = bit.band(multictr, MASK_SUCCESS)
    else
      new_multictr = bit.band(multictr, MASK_FAILURE)
    end

    if new_multictr ~= multictr then
      self.shm:set(counter_key, new_multictr)
    end

    local new_health
    if ctr >= limit then
      new_health = health_report
    elseif current_health == "healthy" and bit.band(new_multictr, MASK_FAILURE) > 0 then
      new_health = "mostly_healthy"
    elseif current_health == "unhealthy" and bit.band(new_multictr, MASK_SUCCESS) > 0 then
      new_health = "mostly_unhealthy"
    end

    if new_health and new_health ~= current_health then
      local state_key = key_for(self.TARGET_STATE, ip, port, hostname)
      self.shm:set(state_key, INTERNAL_STATES[new_health])
      self:raise_event(self.events[new_health], ip, port, hostname)
    end

    return true

  end)

end


--- Report a health failure.
-- Reports a health failure which will count against the number of occurrences
-- required to make a target "fall". The type of healthchecker,
-- "tcp" or "http" (see `new`) determines against which counter the occurence goes.
-- If `unhealthy.tcp_failures` (for TCP failures) or `unhealthy.http_failures`
-- is set to zero in the configuration, this function is a no-op
-- and returns `true`.
-- @param ip IP address of the target being checked.
-- @param port the port being checked against.
-- @param hostname (optional) hostname of the target being checked.
-- @param check (optional) the type of check, either "passive" or "active", default "passive".
-- @return `true` on success, or `nil + error` on failure.
function checker:report_failure(ip, port, hostname, check)

  local checks = self.checks[check or "passive"]
  local limit, ctr_type
  if self.checks[check or "passive"].type == "tcp" then
    limit = checks.unhealthy.tcp_failures
    ctr_type = CTR_TCP
  else
    limit = checks.unhealthy.http_failures
    ctr_type = CTR_HTTP
  end

  return incr_counter(self, "unhealthy", ip, port, hostname, limit, ctr_type)

end


--- Report a health success.
-- Reports a health success which will count against the number of occurrences
-- required to make a target "rise".
-- If `healthy.successes` is set to zero in the configuration,
-- this function is a no-op and returns `true`.
-- @param ip IP address of the target being checked.
-- @param port the port being checked against.
-- @param hostname (optional) hostname of the target being checked.
-- @param check (optional) the type of check, either "passive" or "active", default "passive".
-- @return `true` on success, or `nil + error` on failure.
function checker:report_success(ip, port, hostname, check)

  local limit = self.checks[check or "passive"].healthy.successes

  return incr_counter(self, "healthy", ip, port, hostname, limit, CTR_SUCCESS)

end


--- Report a http response code.
-- How the code is interpreted is based on the configuration for healthy and
-- unhealthy statuses. If it is in neither strategy, it will be ignored.
-- If `healthy.successes` (for healthy HTTP status codes)
-- or `unhealthy.http_failures` (fur unhealthy HTTP status codes)
-- is set to zero in the configuration, this function is a no-op
-- and returns `true`.
-- @param ip IP address of the target being checked.
-- @param port the port being checked against.
-- @param hostname (optional) hostname of the target being checked.
-- @param http_status the http statuscode, or nil to report an invalid http response.
-- @param check (optional) the type of check, either "passive" or "active", default "passive".
-- @return `true` on success, `nil` if the status was ignored (not in active or
-- passive health check lists) or `nil + error` on failure.
function checker:report_http_status(ip, port, hostname, http_status, check)
  http_status = tonumber(http_status) or 0

  local checks = self.checks[check or "passive"]

  local status_type, limit, ctr
  if checks.healthy.http_statuses[http_status] then
    status_type = "healthy"
    limit = checks.healthy.successes
    ctr = CTR_SUCCESS
  elseif checks.unhealthy.http_statuses[http_status]
      or http_status == 0 then
    status_type = "unhealthy"
    limit = checks.unhealthy.http_failures
    ctr = CTR_HTTP
  else
    return
  end

  return incr_counter(self, status_type, ip, port, hostname, limit, ctr)

end

--- Report a failure on TCP level.
-- If `unhealthy.tcp_failures` is set to zero in the configuration,
-- this function is a no-op and returns `true`.
-- @param ip IP address of the target being checked.
-- @param port the port being checked against.
-- @param hostname hostname of the target being checked.
-- @param operation The socket operation that failed:
-- "connect", "send" or "receive".
-- TODO check what kind of information we get from the OpenResty layer
-- in order to tell these error conditions apart
-- https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/balancer.md#get_last_failure
-- @param check (optional) the type of check, either "passive" or "active", default "passive".
-- @return `true` on success, or `nil + error` on failure.
function checker:report_tcp_failure(ip, port, hostname, operation, check)

  local limit = self.checks[check or "passive"].unhealthy.tcp_failures

  -- TODO what do we do with the `operation` information
  return incr_counter(self, "unhealthy", ip, port, hostname, limit, CTR_TCP)

end


--- Report a timeout failure.
-- If `unhealthy.timeouts` is set to zero in the configuration,
-- this function is a no-op and returns `true`.
-- @param ip IP address of the target being checked.
-- @param port the port being checked against.
-- @param hostname (optional) hostname of the target being checked.
-- @param check (optional) the type of check, either "passive" or "active", default "passive".
-- @return `true` on success, or `nil + error` on failure.
function checker:report_timeout(ip, port, hostname, check)

  local limit = self.checks[check or "passive"].unhealthy.timeouts

  return incr_counter(self, "unhealthy", ip, port, hostname, limit, CTR_TIMEOUT)

end


--- Sets the current status of all targets with the given hostname and port.
-- @param hostname hostname being checked.
-- @param port the port being checked against
-- @param is_healthy boolean: `true` for healthy, `false` for unhealthy
-- @return `true` on success, or `nil + error` on failure.
function checker:set_all_target_statuses_for_hostname(hostname, port, is_healthy)
  assert(type(hostname) == "string", "no hostname provided")
  port = assert(tonumber(port), "no port number provided")
  assert(type(is_healthy) == "boolean")

  local all_ok = true
  local errs = {}
  for _, target in ipairs(self.targets) do
    if target.port == port and target.hostname == hostname then
      local ok, err = self:set_target_status(target.ip, port, hostname, is_healthy)
      if not ok then
        all_ok = nil
        table.insert(errs, err)
      end
    end
  end

  return all_ok, #errs > 0 and table.concat(errs, "; ") or nil
end


--- Sets the current status of the target.
-- This will immediately set the status and clear its counters.
-- @param ip IP address of the target being checked
-- @param port the port being checked against
-- @param hostname (optional) hostname of the target being checked.
-- @param is_healthy boolean: `true` for healthy, `false` for unhealthy
-- @return `true` on success, or `nil + error` on failure
function checker:set_target_status(ip, port, hostname, is_healthy)
  ip   = tostring(assert(ip, "no ip address provided"))
  port = assert(tonumber(port), "no port number provided")
  assert(type(is_healthy) == "boolean")
  hostname = hostname or ip

  local health_report = is_healthy and "healthy" or "unhealthy"

  local target = get_target(self, ip, port, hostname)
  if not target then
    -- sync issue: warn, but return success
    self:log(WARN, "trying to set status for a target that is not in the list: ", ip, ":", port)
    return true
  end

  local counter_key = key_for(self.TARGET_COUNTER, ip, port, hostname)
  local state_key = key_for(self.TARGET_STATE, ip, port, hostname)

  local ok, err = locking_target(self, ip, port, hostname, function()

    local _, err = self.shm:set(counter_key, 0)
    if err then
      return nil, err
    end

    self.shm:set(state_key, INTERNAL_STATES[health_report])
    if err then
      return nil, err
    end

    self:raise_event(self.events[health_report], ip, port, hostname)

    return true

  end)

  if ok then
    self:log(WARN, health_report, " forced for ", hostname, " ", ip, ":", port)
  end
  return ok, err
end


-- Introspection function for testing
local function test_get_counter(self, ip, port, hostname)
  return locking_target(self, ip, port, hostname, function()
    local counter = self.shm:get(key_for(self.TARGET_COUNTER, ip, port, hostname))
    local internal_health = (get_target(self, ip, port, hostname) or EMPTY).internal_health
    return counter, internal_health
  end)
end


--============================================================================
-- Healthcheck runner
--============================================================================


-- Runs a single healthcheck probe
function checker:run_single_check(ip, port, hostname, hostheader)

  -- Count the attempt *before* the check runs, not after: a readiness gate
  -- needs to know how many consecutive active-check attempts have actually
  -- been dispatched for this target (success, failure, or timeout all count),
  -- not whether any one of them succeeded. A single attempt is not enough on
  -- its own -- with e.g. unhealthy.http_failures = 2 configured, the target's
  -- real internal_health only converges after two consecutive attempts, so
  -- the gate needs the count, not just a boolean "was it ever probed".
  -- Written to shm (not a local field) since a readiness probe can land on
  -- any worker, not just whichever one holds the periodic-probe lock and
  -- runs this function.
  local probed_key = key_for(self.TARGET_PROBED, ip, port, hostname)
  local probed_ok, probed_err = self.shm:incr(probed_key, 1, 0)
  if not probed_ok then
    self:log(ERR, "failed to increment probe count in shm: ", probed_err)
  end

  local sock, err = ngx.socket.tcp()
  if not sock then
    self:log(ERR, "failed to create stream socket: ", err)
    return
  end

  sock:settimeout(self.checks.active.timeout * 1000)

  local ok
  ok, err = sock:connect(ip, port)
  if not ok then
    if err == "timeout" then
      sock:close()  -- timeout errors do not close the socket.
      return self:report_timeout(ip, port, hostname, "active")
    end
    return self:report_tcp_failure(ip, port, hostname, "connect", "active")
  end

  if self.checks.active.type == "tcp" then
    sock:close()
    return self:report_success(ip, port, hostname, "active")
  end

  if self.checks.active.type == "https" then
    local https_sni, session, err
    https_sni = self.checks.active.https_sni or hostheader or hostname
    if self.ssl_cert and self.ssl_key then
      ok, err = sock:setclientcert(self.ssl_cert, self.ssl_key)

      if not ok then
        self:log(ERR, "failed to set client certificate: ", err)
      end
    end

    session, err = sock:sslhandshake(nil, https_sni,
                                     self.checks.active.https_verify_certificate)

    if not session then
      sock:close()
      self:log(ERR, "failed SSL handshake with '", hostname or "", " (", ip, ":", port, ")', using server name (sni) '", https_sni, "': ", err)
      return self:report_tcp_failure(ip, port, hostname, "connect", "active")
    end

  end

  local req_headers = self.checks.active.req_headers
  local headers
  if self.checks.active._headers_str then
    headers = self.checks.active._headers_str
  else
    local headers_length = nkeys(req_headers)
    if headers_length > 0 then
      if is_array(req_headers) then
        self:log(WARN, "array headers is deprecated")
        headers = table.concat(req_headers, "\r\n")
      else
        headers = new_tab(0, headers_length)
        local idx = 0
        for key, values in pairs(req_headers) do
            if type(values) == "table" then
              for _, value in ipairs(values) do
                idx = idx + 1
                headers[idx] = key .. ": " .. tostring(value)
              end
            else
              idx = idx + 1
              headers[idx] = key .. ": " .. tostring(values)
            end
        end
        headers = table.concat(headers, "\r\n")
      end
      if #headers > 0 then
        headers = headers .. "\r\n"
      end
    end
    self.checks.active._headers_str = headers or ""
  end

  local method = self.checks.active.http_method
  local path = self.checks.active.http_path
  local body = self.checks.active.http_req_body
  local final_hostheader = hostheader or hostname or ip
  local request
  if body and #body > 0 then
    request = ("%s %s HTTP/1.1\r\nConnection: close\r\n%sHost: %s\r\nContent-Length: %d\r\n\r\n%s")
              :format(method, path, headers, final_hostheader, #body, body)
  else
    request = ("%s %s HTTP/1.1\r\nConnection: close\r\n%sHost: %s\r\n\r\n")
              :format(method, path, headers, final_hostheader)
  end
  self:log(DEBUG, "request: ", request)

  local bytes
  bytes, err = sock:send(request)
  if not bytes then
    self:log(ERR, "failed to send http request to '", hostname, " (", ip, ":", port, ")': ", err)
    if err == "timeout" then
      sock:close()  -- timeout errors do not close the socket.
      return self:report_timeout(ip, port, hostname, "active")
    end
    return self:report_tcp_failure(ip, port, hostname, "send", "active")
  end

  local status_line
  status_line, err = sock:receive()
  if not status_line then
    self:log(ERR, "failed to receive status line from '", hostname, " (",ip, ":", port, ")': ", err)
    if err == "timeout" then
      sock:close()  -- timeout errors do not close the socket.
      return self:report_timeout(ip, port, hostname, "active")
    end
    return self:report_tcp_failure(ip, port, hostname, "receive", "active")
  end

  local from, to = re_find(status_line,
                          [[^HTTP/\d+\.\d+\s+(\d+)]],
                          "joi", nil, 1)
  local status
  if from then
    status = tonumber(status_line:sub(from, to))
  else
    self:log(ERR, "bad status line from '", hostname, " (", ip, ":", port, ")': ", status_line)
    -- note: 'status' will be reported as 'nil'
  end

  sock:close()

  self:log(DEBUG, "Reporting '", hostname, " (", ip, ":", port, ")' (got HTTP ", status, ")")

  return self:report_http_status(ip, port, hostname, status, "active")
end

-- executes a work package (a list of checks) sequentially
function checker:run_work_package(work_package)
  for _, work_item in ipairs(work_package) do
    self:log(DEBUG, "Checking ", work_item.hostname, " ",
                    work_item.hostheader and "(host header: ".. work_item.hostheader .. ")"
                    or "", work_item.ip, ":", work_item.port,
                    " (currently ", work_item.debug_health, ")")
    local hostheader = work_item.hostheader or work_item.hostname
    self:run_single_check(work_item.ip, work_item.port, work_item.hostname, hostheader)
  end
end

-- runs the active healthchecks concurrently, in multiple work packages.
-- @param list the list of targets to check
function checker:active_check_targets(list)
  local idx = 1
  local work_packages = {}

  for _, work_item in ipairs(list) do
    local package = work_packages[idx]
    if not package then
      package = {}
      work_packages[idx] = package
    end
    package[#package + 1] = work_item
    idx = idx + 1
    if idx > self.checks.active.concurrency then idx = 1 end
  end

  -- hand out work-packages to the threads, note the "-1" because this timer
  -- thread will handle the last package itself.
  local threads = {}
  for i = 1, #work_packages - 1 do
    threads[i] = ngx.thread.spawn(self.run_work_package, self, work_packages[i])
  end
  -- run last package myself
  self:run_work_package(work_packages[#work_packages])

  -- wait for everybody to finish
  for _, thread in ipairs(threads) do
    ngx.thread.wait(thread)
  end
end

--============================================================================
-- Internal callbacks, timers and events
--============================================================================
-- The timer callbacks are responsible for checking the status, upon success/
-- failure they will call the health-management functions to deal with the
-- results of the checks.


-- @return `true` on success, or false if the lock was not acquired, or `nil + error`
-- in case of errors
local function get_periodic_lock(shm, key)
  local my_pid = ngx_worker_pid()
  local checker_pid = shm:get(key)

  if checker_pid == nil then
    -- no worker is checking, try to acquire the lock
    local ok, err = shm:add(key, my_pid, LOCK_PERIOD)
    if not ok then
      if err == "exists" then
        -- another worker got the lock before
        return false
      end
      ngx_log(ERR, "failed to add key '", key, "': ", err)
      return nil, err
    end
  elseif checker_pid ~= my_pid then
    -- another worker is checking
    return false
  end

  return true
end


-- touch the shm to refresh the valid period
local function renew_periodic_lock(shm, key)
  local my_pid = ngx_worker_pid()

  local _, err = shm:set(key, my_pid, LOCK_PERIOD)
  if err then
    ngx_log(ERR, "failed to update key '", key, "': ", err)
  end
end


--- Active health check callback function.
-- @param self the checker object this timer runs on
-- @param health_mode either "healthy" or "unhealthy" to indicate what check
local function checker_callback(self, health_mode)
  if self.checker_callback_count then
    self.checker_callback_count = self.checker_callback_count + 1
  end

  local list_to_check = {}
  local targets, err = fetch_target_list(self)
  if not targets then
    self:log(ERR, "checker_callback: ", err)
    return
  end

  for _, target in ipairs(targets) do
    local tgt = get_target(self, target.ip, target.port, target.hostname)
    local internal_health = tgt and tgt.internal_health or nil
    if (health_mode == "healthy" and (internal_health == "healthy" or
                                      internal_health == "mostly_healthy"))
    or (health_mode == "unhealthy" and (internal_health == "unhealthy" or
                                        internal_health == "mostly_unhealthy"))
    then
      list_to_check[#list_to_check + 1] = {
        ip = target.ip,
        port = target.port,
        hostname = target.hostname,
        hostheader = target.hostheader,
        meta = target.meta,
        debug_health = internal_health,
      }
    end
  end

  if not list_to_check[1] then
    self:log(DEBUG, "checking ", health_mode, " targets: nothing to do")
  else
    local timer = resty_timer({
      interval = 0,
      recurring = false,
      immediate = false,
      detached = true,
      expire = function()
        self:log(DEBUG, "checking ", health_mode, " targets: #", #list_to_check)
        self:active_check_targets(list_to_check)
      end,
    })
    if timer == nil then
      self:log(ERR, "failed to create timer to check ", health_mode)
    end
  end
end

-- Event handler callback
function checker:event_handler(event_name, ip, port, hostname)

  local target_found = get_target(self, ip, port, hostname)

  if event_name == self.events.remove then
    if target_found then
      -- remove hash part
      self.targets[target_found.ip][target_found.port][target_found.hostname] = nil
      if not next(self.targets[target_found.ip][target_found.port]) then
        -- no more hostnames on this port, so delete it
        self.targets[target_found.ip][target_found.port] = nil
      end
      if not next(self.targets[target_found.ip]) then
        -- no more ports on this ip, so delete it
        self.targets[target_found.ip] = nil
      end
      -- remove from list part
      for i, target in ipairs(self.targets) do
        if target.ip == ip and target.port == port and
          target.hostname == hostname then
          table_remove(self.targets, i)
          break
        end
      end
      self:log(DEBUG, "event: target '", hostname or "", " (", ip, ":", port,
                      ")' removed")

    else
      self:log(WARN, "event: trying to remove an unknown target '",
                      hostname or "", "(", ip, ":", port, ")'")
    end

  elseif event_name == self.events.healthy or
         event_name == self.events.mostly_healthy or
         event_name == self.events.unhealthy or
         event_name == self.events.mostly_unhealthy
         then
    if not target_found then
      -- it is a new target, must add it first
      target_found = { ip = ip, port = port, hostname = hostname or ip }
      self.targets[target_found.ip] = self.targets[target_found.ip] or {}
      self.targets[target_found.ip][target_found.port] = self.targets[target_found.ip][target_found.port] or {}
      self.targets[target_found.ip][target_found.port][target_found.hostname] = target_found
      self.targets[#self.targets + 1] = target_found
      self:log(DEBUG, "event: target added '", hostname or "", "(", ip, ":", port, ")'")
    end
    do
      local from_status = target_found.internal_health
      local to_status = event_name
      local from = from_status == "healthy" or from_status == "mostly_healthy"
      local to = to_status == "healthy" or to_status == "mostly_healthy"

      if from ~= to then
        self.status_ver = self.status_ver + 1
      end

      self:log(DEBUG, "event: target status '", hostname or "", "(", ip, ":",
                port, ")' from '", from, "' to '", to, "', ver: ", self.status_ver)
    end
    target_found.internal_health = event_name

  elseif event_name == self.events.clear then
    -- clear local cache
    self.targets = {}
    self:log(DEBUG, "event: local cache cleared")

  else
    self:log(WARN, "event: unknown event received '", event_name, "'")
  end
end


-- Re-derive a checker's local internal_health for every target the shm target
-- list says exists, correcting any target whose cached value has drifted from
-- a worker_events broadcast this worker never received (apache/apisix#13888),
-- AND backfilling any target this worker's self.targets never even contains
-- an entry for at all.
--
-- The second case is not hypothetical: add_target()'s "already exists in shm"
-- branch (see its own comment) returns early without ever calling raise_event,
-- so a worker whose *own* add_target call loses that race gets no event either
-- -- and if this worker's initial checker.new() read of the target list also
-- raced ahead of the writer (observed directly: "Got initial target list (0
-- targets)" immediately followed by "adding an existing target ... (ignoring)"
-- for every target), self.targets ends up with no entry for that target at
-- all: not stale, structurally absent. Since checker_callback() only ever
-- looks a target up via get_target(self, ...) against this same self.targets,
-- such a target is permanently invisible to this worker's active-check cycle
-- -- if this worker also holds the periodic probe lock (which never
-- voluntarily rotates), NO worker ever probes that target again for the life
-- of the process. Sourcing this sweep from fetch_target_list() (shm, the
-- authoritative source used across the file, e.g. add_target/checker_callback
-- itself) instead of iterating self.targets directly is what lets a missing
-- entry be detected in the first place.
local function reconcile_target_health(checker_obj)
  local targets, err = fetch_target_list(checker_obj)
  if not targets then
    checker_obj:log(ERR, "reconcile: failed to fetch target list from shm: ", err)
    return
  end

  for _, target in ipairs(targets) do
    local state_key = key_for(checker_obj.TARGET_STATE, target.ip, target.port,
                               target.hostname)
    local raw_state = checker_obj.shm:get(state_key)
    -- add_target() always writes TARGET_STATE before a target is considered
    -- live (see its comment), so nil here means this read raced a concurrent
    -- add/remove, not a genuine absence of state -- skip it for this sweep,
    -- it will be consistent again on the next one.
    if raw_state ~= nil then
      local shm_health = INTERNAL_STATES[raw_state]
      if shm_health then
        local target_found = get_target(checker_obj, target.ip, target.port, target.hostname)
        if not target_found then
          -- lazily insert, mirroring event_handler's own "it is a new target,
          -- must add it first" branch -- keeps both the ip/port/hostname
          -- lookup table and the array part (used elsewhere, e.g. remove)
          -- consistent with how every other insertion path populates them.
          target_found = { ip = target.ip, port = target.port,
                            hostname = target.hostname or target.ip }
          checker_obj.targets[target_found.ip] = checker_obj.targets[target_found.ip] or {}
          checker_obj.targets[target_found.ip][target_found.port] =
            checker_obj.targets[target_found.ip][target_found.port] or {}
          checker_obj.targets[target_found.ip][target_found.port][target_found.hostname] =
            target_found
          checker_obj.targets[#checker_obj.targets + 1] = target_found
          checker_obj:log(WARN, "reconciled missing target from shm (never seen locally) '",
                          target_found.hostname or "", "(", target_found.ip, ":",
                          target_found.port, ")' as '", shm_health, "'")
        elseif shm_health ~= target_found.internal_health then
          local from = target_found.internal_health == "healthy" or
                       target_found.internal_health == "mostly_healthy"
          local to = shm_health == "healthy" or shm_health == "mostly_healthy"
          if from ~= to then
            checker_obj.status_ver = checker_obj.status_ver + 1
          end
          checker_obj:log(WARN, "reconciled target status from shm (missed event) '",
                          target_found.hostname or "", "(", target_found.ip, ":",
                          target_found.port, ")' from '", target_found.internal_health,
                          "' to '", shm_health, "'")
        end
        target_found.internal_health = shm_health
      end
    end
  end
end


------------------------------------------------------------------------------
-- Initializing.
-- @section initializing
------------------------------------------------------------------------------

-- Log a message specific to this checker
-- @param level standard ngx log level constant
function checker:log(level, ...)
  ngx_log(level, worker_color(self.LOG_PREFIX), ...)
end


-- Raises an event for a target status change.
function checker:raise_event(event_name, ip, port, hostname)
  local target = { ip = ip, port = port, hostname = hostname }
  worker_events.post(self.EVENT_SOURCE, event_name, target)
end


--- Stop the background health checks.
-- The timers will be flagged to exit, but will not exit immediately. Only
-- after the current timers have expired they will be marked as stopped.
-- @return `true`
function checker:stop()
  self.checks.active.healthy.active = false
  self.checks.active.unhealthy.active = false
  worker_events.unregister(self.ev_callback, self.EVENT_SOURCE)
  self:log(DEBUG, "healthchecker stopped")
  return true
end


--- Start the background health checks.
-- @return `true`, or `nil + error`.
function checker:start()
  if self.checks.active.healthy.interval > 0 then
    self.checks.active.healthy.active = true
    -- the first active check happens only after `interval`
    self.checks.active.healthy.last_run = ngx_now()
  end

  if self.checks.active.unhealthy.interval > 0 then
    self.checks.active.unhealthy.active = true
    self.checks.active.unhealthy.last_run = ngx_now()
  end

  worker_events.unregister(self.ev_callback, self.EVENT_SOURCE)  -- ensure we never double subscribe
  worker_events.register_weak(self.ev_callback, self.EVENT_SOURCE)

  self:log(DEBUG, "active check flagged as active")
  return true
end


--============================================================================
-- Create health-checkers
--============================================================================


local NO_DEFAULT = {}
local MAXNUM = 2^31 - 1


local function fail(ctx, k, msg)
  ctx[#ctx + 1] = k
  error(table.concat(ctx, ".") .. ": " .. msg, #ctx + 1)
end


local function fill_in_settings(opts, defaults, ctx)
  ctx = ctx or {}
  local obj = {}
  for k, default in pairs(defaults) do
    local v = opts[k]

    -- basic type-check of configuration
    if default ~= NO_DEFAULT
       and v ~= nil
       and type(v) ~= type(default) then
      fail(ctx, k, "invalid value")
    end

    if v ~= nil then
      if type(v) == "table" then
        if default[1] then -- do not recurse on arrays
          obj[k] = v
        else
          ctx[#ctx + 1] = k
          obj[k] = fill_in_settings(v, default, ctx)
          ctx[#ctx + 1] = nil
        end
      else
        if type(v) == "number" and (v < 0 or v > MAXNUM) then
          fail(ctx, k, "must be between 0 and " .. MAXNUM)
        end
        obj[k] = v
      end
    elseif default ~= NO_DEFAULT then
      obj[k] = deepcopy(default)
    end

  end
  return obj
end


local defaults = {
  name = NO_DEFAULT,
  shm_name = NO_DEFAULT,
  type = NO_DEFAULT,
  status_ver = 0,
  events_module = "resty.worker.events",
  checks = {
    active = {
      type = "http",
      timeout = 1,
      concurrency = 10,
      http_method = "GET",
      http_path = "/",
      http_req_body = "",
      https_sni = NO_DEFAULT,
      https_verify_certificate = true,
      headers = {""},
      healthy = {
        interval = 0, -- 0 = disabled by default
        http_statuses = { 200, 302 },
        successes = 2,
      },
      unhealthy = {
        interval = 0, -- 0 = disabled by default
        http_statuses = { 429, 404,
                          500, 501, 502, 503, 504, 505 },
        tcp_failures = 2,
        timeouts = 3,
        http_failures = 5,
      },
      req_headers = {""},
    },
    passive = {
      type = "http",
      healthy = {
        http_statuses = { 200, 201, 202, 203, 204, 205, 206, 207, 208, 226,
                          300, 301, 302, 303, 304, 305, 306, 307, 308 },
        successes = 5,
      },
      unhealthy = {
        http_statuses = { 429, 500, 503 },
        tcp_failures = 2,
        timeouts = 7,
        http_failures = 5,
      },
    },
  },
}


local function to_set(tbl, key)
  local set = {}
  for _, item in ipairs(tbl[key]) do
    set[item] = true
  end
  tbl[key] = set
end


local check_valid_type
do
  local valid_types = {
    http = true,
    tcp = true,
    https = true,
  }
  check_valid_type = function(var, val)
    assert(valid_types[val],
           var .. " can only be 'http', 'https' or 'tcp', got '" ..
           tostring(val) .. "'")
  end
end

--- Creates a new health-checker instance.
-- It will be started upon creation.
--
-- *NOTE*: the returned `checker` object must be anchored, if not it will be
-- removed by Lua's garbage collector and the healthchecks will cease to run.
-- @param opts table with checker options. Options are:
--
-- * `name`: name of the health checker
-- * `shm_name`: the name of the `lua_shared_dict` specified in the Nginx configuration to use
-- * `ssl_cert`: certificate for mTLS connections (string or parsed object)
-- * `ssl_key`: key for mTLS connections (string or parsed object)
-- * `checks.active.type`: "http", "https" or "tcp" (default is "http")
-- * `checks.active.timeout`: socket timeout for active checks (in seconds)
-- * `checks.active.concurrency`: number of targets to check concurrently
-- * `checks.active.http_method`: method to use in the HTTP request to run on active checks (default is `GET`)
-- * `checks.active.http_path`: path to use in the HTTP request to run on active checks
-- * `checks.active.http_req_body`: body to send in the HTTP request to run on active checks (a non-empty body adds a `Content-Length` header)
-- * `checks.active.https_sni`: SNI server name incase of HTTPS
-- * `checks.active.https_verify_certificate`: boolean indicating whether to verify the HTTPS certificate
-- * `checks.active.headers`: one or more lists of values indexed by header name
-- * `checks.active.healthy.interval`: interval between checks for healthy targets (in seconds)
-- * `checks.active.healthy.http_statuses`: which HTTP statuses to consider a success
-- * `checks.active.healthy.successes`: number of successes to consider a target healthy
-- * `checks.active.unhealthy.interval`: interval between checks for unhealthy targets (in seconds)
-- * `checks.active.unhealthy.http_statuses`: which HTTP statuses to consider a failure
-- * `checks.active.unhealthy.tcp_failures`: number of TCP failures to consider a target unhealthy
-- * `checks.active.unhealthy.timeouts`: number of timeouts to consider a target unhealthy
-- * `checks.active.unhealthy.http_failures`: number of HTTP failures to consider a target unhealthy
-- * `checks.passive.type`: "http", "https" or "tcp" (default is "http"; for passive checks, "http" and "https" are equivalent)
-- * `checks.passive.healthy.http_statuses`: which HTTP statuses to consider a failure
-- * `checks.passive.healthy.successes`: number of successes to consider a target healthy
-- * `checks.passive.unhealthy.http_statuses`: which HTTP statuses to consider a success
-- * `checks.passive.unhealthy.tcp_failures`: number of TCP failures to consider a target unhealthy
-- * `checks.passive.unhealthy.timeouts`: number of timeouts to consider a target unhealthy
-- * `checks.passive.unhealthy.http_failures`: number of HTTP failures to consider a target unhealthy
--
-- If any of the health counters above (e.g. `checks.passive.unhealthy.timeouts`)
-- is set to zero, the according category of checks is not taken to account.
-- This way active or passive health checks can be disabled selectively.
--
-- @return checker object, or `nil + error`
function _M.new(opts)

  opts = opts or {}
  local active_type = (((opts or EMPTY).checks or EMPTY).active or EMPTY).type
  local passive_type = (((opts or EMPTY).checks or EMPTY).passive or EMPTY).type

  local self = fill_in_settings(opts, defaults)

  load_events_module(self)

  -- If using deprecated self.type, that takes precedence over
  -- a default value. TODO: remove this in a future version
  if self.type then
    self.checks.active.type = active_type or self.type
    self.checks.passive.type = passive_type or self.type
    check_valid_type("type", self.type)
  end

  assert(self.checks.active.healthy.successes < 255,        "checks.active.healthy.successes must be at most 254")
  assert(self.checks.active.unhealthy.tcp_failures < 255,   "checks.active.unhealthy.tcp_failures must be at most 254")
  assert(self.checks.active.unhealthy.http_failures < 255,  "checks.active.unhealthy.http_failures must be at most 254")
  assert(self.checks.active.unhealthy.timeouts < 255,       "checks.active.unhealthy.timeouts must be at most 254")
  assert(self.checks.passive.healthy.successes < 255,       "checks.passive.healthy.successes must be at most 254")
  assert(self.checks.passive.unhealthy.tcp_failures < 255,  "checks.passive.unhealthy.tcp_failures must be at most 254")
  assert(self.checks.passive.unhealthy.http_failures < 255, "checks.passive.unhealthy.http_failures must be at most 254")
  assert(self.checks.passive.unhealthy.timeouts < 255,      "checks.passive.unhealthy.timeouts must be at most 254")

  if opts.test then
    self.test_get_counter = test_get_counter
    self.checker_callback_count = 0
  end

  assert(self.name, "required option 'name' is missing")
  assert(self.shm_name, "required option 'shm_name' is missing")

  check_valid_type("checks.active.type", self.checks.active.type)
  check_valid_type("checks.passive.type", self.checks.passive.type)

  self.shm = ngx.shared[tostring(opts.shm_name)]
  assert(self.shm, ("no shm found by name '%s'"):format(opts.shm_name))

  -- load certificate and key
  if opts.ssl_cert and opts.ssl_key then
    if type(opts.ssl_cert) == "cdata" then
      self.ssl_cert = opts.ssl_cert
    else
      self.ssl_cert = assert(ssl.parse_pem_cert(opts.ssl_cert))
    end

    if type(opts.ssl_key) == "cdata" then
      self.ssl_key = opts.ssl_key
    else
      self.ssl_key = assert(ssl.parse_pem_priv_key(opts.ssl_key))
    end

  end

  -- other properties
  self.targets = nil     -- list of targets, initially loaded, maintained by events
  self.events = nil      -- hash table with supported events (prevent magic strings)
  self.ev_callback = nil -- callback closure per checker instance

  -- Convert status lists to sets
  to_set(self.checks.active.unhealthy, "http_statuses")
  to_set(self.checks.active.healthy, "http_statuses")
  to_set(self.checks.passive.unhealthy, "http_statuses")
  to_set(self.checks.passive.healthy, "http_statuses")

  -- decorate with methods and constants
  self.events = EVENTS
  for k,v in pairs(checker) do
    self[k] = v
  end

  -- prepare shm keys
  self.TARGET_STATE     = SHM_PREFIX .. self.name .. ":state"
  self.TARGET_COUNTER   = SHM_PREFIX .. self.name .. ":counter"
  self.TARGET_LIST      = SHM_PREFIX .. self.name .. ":target_list"
  self.TARGET_LIST_LOCK = SHM_PREFIX .. self.name .. ":target_list_lock"
  self.TARGET_LOCK      = SHM_PREFIX .. self.name .. ":target_lock"
  self.TARGET_PROBED    = SHM_PREFIX .. self.name .. ":probed"
  self.PERIODIC_LOCK    = SHM_PREFIX .. ":period_lock:"
  -- prepare constants
  self.EVENT_SOURCE     = EVENT_SOURCE_PREFIX .. " [" .. self.name .. "]"
  self.LOG_PREFIX       = LOG_PREFIX .. "(" .. self.name .. ") "

  -- register for events, and directly after load initial target list
  -- order is important!
  do
    -- Lock the list, in case it is being cleared by another worker
    local ok, err = locking_target_list(self, function(target_list)

      self.targets = target_list
      self:log(DEBUG, "Got initial target list (", #self.targets, " targets)")

      -- load individual statuses
      for _, target in ipairs(self.targets) do
        local state_key = key_for(self.TARGET_STATE, target.ip, target.port, target.hostname)
        target.internal_health = INTERNAL_STATES[self.shm:get(state_key)]
        self:log(DEBUG, "Got initial status ", target.internal_health, " ",
                        target.hostname, " ", target.ip, ":", target.port)
        -- fill-in the hash part for easy lookup
        self.targets[target.ip] = self.targets[target.ip] or {}
        self.targets[target.ip][target.port] = self.targets[target.ip][target.port] or {}
        self.targets[target.ip][target.port][target.hostname or target.ip] = target
      end

      return true
    end)
    if not ok then
      -- locking failed, we don't protect `targets` of being nil in other places
      -- so consider this as not recoverable
      return nil, "Error loading initial target list: " .. err
    end

    self.ev_callback = function(data, event)
      -- just a wrapper to be able to access `self` as a closure
      return self:event_handler(event, data.ip, data.port, data.hostname)
    end

    -- handle events to sync up in case there was a change by another worker
    worker_events:poll()
  end

  -- turn on active health check
  local ok, err = self:start()
  if not ok then
    self:stop()
    return nil, err
  end

  -- if active checker is not running, start it
  if active_check_timer == nil then

    self:log(DEBUG, "worker ", ngx_worker_id(), " (pid: ", ngx_worker_pid(), ") ",
      "starting active check timer")
    local shm, key = self.shm, self.PERIODIC_LOCK
    local cleanup_key = key .. ":cleanup"
    active_check_timer, err = resty_timer({
      recurring = true,
      interval = CHECK_INTERVAL,
      jitter = CHECK_JITTER,
      detached = false,
      expire = function()

        local cur_time = ngx_now()

        -- Self-heal from a missed worker_events broadcast (apache/apisix#13888).
        -- Unlike the probing/cleanup elections below, this runs on EVERY worker
        -- EVERY tick it's due, regardless of who owns the periodic/cleanup
        -- locks -- a worker with no active checker of its own can still be
        -- routing traffic off a stale cached status for a checker it merely
        -- reads (get_target_status), so it must reconcile too.
        if cur_time - last_reconcile_time >= RECONCILE_INTERVAL then
          last_reconcile_time = cur_time
          for _, checker_obj in pairs(hcs) do
            reconcile_target_health(checker_obj)
          end
        end

        -- Stale-target cleanup is decoupled from active probing and the
        -- periodic lock. A passive-only deployment (checks.passive but no
        -- active interval) has no active checker on any worker, yet still marks
        -- targets via delayed_clear() and must purge them; gating cleanup on
        -- the periodic lock (which only an active worker ever holds) would leak
        -- those targets forever (apache/apisix#13385).
        --
        -- A single worker per window is elected via an atomic shm:add on
        -- cleanup_key (TTL = CLEANUP_INTERVAL): any worker can win, including a
        -- passive-only one, so the leak fix holds, while the other workers skip
        -- the pass and do not all contend on each checker's TARGET_LIST_LOCK.
        -- The elected worker purges every checker in its own `hcs` in one pass.
        -- Purging writes to the shared shm target_list, so cleaning a checker on
        -- any one worker is globally effective; if checkers are distributed
        -- asymmetrically across workers, a given upstream is purged in whichever
        -- window a worker that owns its checker wins the election -- eventually
        -- consistent rather than every-worker-every-window.
        local won, add_err = shm:add(cleanup_key, ngx_worker_pid(), CLEANUP_INTERVAL)
        if won then
          for _, checker_obj in pairs(hcs) do
            -- clear targets marked for delayed removal
            locking_target_list(checker_obj, function(target_list)
              local removed_targets = {}
              local index = 1
              while index <= #target_list do
                local target = target_list[index]
                if target.purge_time and target.purge_time <= cur_time then
                  table_insert(removed_targets, target)
                  table_remove(target_list, index)
                else
                  index = index + 1
                end
              end

              if #removed_targets > 0 then
                target_list = serialize(target_list)

                local ok, err = shm:set(checker_obj.TARGET_LIST, target_list)
                if not ok then
                  return nil, "failed to store target_list in shm: " .. err
                end

                for _, target in ipairs(removed_targets) do
                  clear_target_data_from_shm(checker_obj, target.ip, target.port, target.hostname)
                  checker_obj:raise_event(checker_obj.events.remove, target.ip, target.port, target.hostname)
                end
              end
            end)
          end
        elseif add_err ~= "exists" then
          ngx_log(ERR, "failed to elect cleanup worker for '", cleanup_key, "': ", add_err)
        end

        -- The periodic lock distributes ACTIVE probing to a single worker. A
        -- worker with no active checker must release the lock (if it holds it)
        -- and back off, so a worker that still owns active checkers can take
        -- over; otherwise active health checks stay stuck after a disable ->
        -- re-enable cycle (apache/apisix#13235). This is gated on
        -- has_active_checker rather than on `hcs` being non-empty, because a
        -- disabled checker lingers in the weak `hcs` table with active=false
        -- until it is garbage collected.
        local has_active_checker = false
        for _, checker_obj in pairs(hcs) do
          if checker_obj.checks.active.healthy.active or
             checker_obj.checks.active.unhealthy.active then
            has_active_checker = true
            break
          end
        end

        if not has_active_checker then
          -- release the lock only if we are still the holder, so a worker that
          -- still owns active checkers can take over
          if shm:get(key) == ngx_worker_pid() then
            shm:delete(key)
          end
          return
        end

        if get_periodic_lock(shm, key) then
          renew_periodic_lock(shm, key)
        else
          return
        end

        -- active probing: only the periodic-lock holder runs the probes
        for _, checker_obj in pairs(hcs) do
          if checker_obj.checks.active.healthy.active and
            (checker_obj.checks.active.healthy.last_run +
              checker_obj.checks.active.healthy.interval <= cur_time)
          then
            checker_obj.checks.active.healthy.last_run = cur_time
            checker_callback(checker_obj, "healthy")
          end

          if checker_obj.checks.active.unhealthy.active and
            (checker_obj.checks.active.unhealthy.last_run +
              checker_obj.checks.active.unhealthy.interval <= cur_time)
          then
            checker_obj.checks.active.unhealthy.last_run = cur_time
            checker_callback(checker_obj, "unhealthy")
          end
        end
      end,
    })
    if not active_check_timer then
      self:log(ERR, "Could not start active check timer: ", err)
    end
  end

  table.insert(hcs, self)

  -- TODO: push entire config in debug level logs
  self:log(DEBUG, "Healthchecker started!")
  return self
end


function _M.get_target_list(name, shm_name)
  local self = {
    name = name,
    shm_name = shm_name,
    log = checker.log,
  }
  self.shm = ngx.shared[tostring(shm_name)]
  assert(self.shm, ("no shm found by name '%s'"):format(shm_name))
  self.TARGET_STATE     = SHM_PREFIX .. self.name .. ":state"
  self.TARGET_COUNTER   = SHM_PREFIX .. self.name .. ":counter"
  self.TARGET_LIST      = SHM_PREFIX .. self.name .. ":target_list"
  self.TARGET_LIST_LOCK = SHM_PREFIX .. self.name .. ":target_list_lock"
  self.TARGET_PROBED    = SHM_PREFIX .. self.name .. ":probed"
  self.LOG_PREFIX       = LOG_PREFIX .. "(" .. self.name .. ") "

  local ok, err = locking_target_list(self, function(target_list)
    self.targets = target_list
    for _, target in ipairs(self.targets) do
      local state_key = key_for(self.TARGET_STATE, target.ip, target.port, target.hostname)
      target.status = INTERNAL_STATES[self.shm:get(state_key)]
      local probed_key = key_for(self.TARGET_PROBED, target.ip, target.port, target.hostname)
      target.probe_count = self.shm:get(probed_key) or 0
      if not target.hostheader then
        target.hostheader = nil
      end
    end

    return true
  end)

  for _, target in ipairs(self.targets) do
    local key = key_for(self.TARGET_LOCK, target.ip, target.port, target.hostname)
    local ok = run_locked(self, key, function()
      local counter = self.shm:get(key_for(self.TARGET_COUNTER,
        target.ip, target.port, target.hostname))
      target.counter = {
        success = ctr_get(counter, CTR_SUCCESS),
        http_failure = ctr_get(counter, CTR_HTTP),
        tcp_failure = ctr_get(counter, CTR_TCP),
        timeout_failure = ctr_get(counter, CTR_TIMEOUT),
      }
      return true
    end)

    if not ok then
      target.counter = {
        success = 0,
        http_failure = 0,
        tcp_failure = 0,
        timeout_failure = 0,
      }
    end
  end

  if not ok then
    return nil, "Error loading target list: " .. err
  end

  return self.targets
end


-- Returns true only if the checker has at least one target AND every one of
-- them has had at least `min_attempts` consecutive active-check attempts
-- ("probed" means attempted, not "healthy" -- a failed or timed-out check
-- still counts toward the count). false if there are no targets yet (nothing
-- to probe) or any target has not yet reached min_attempts. nil+err on a shm
-- read failure, mirroring get_target_list's own error contract.
--
-- min_attempts defaults to 1 for backward compatibility, but a caller that
-- knows the checker's own unhealthy/healthy thresholds should pass the
-- worst-case one: with e.g. unhealthy.http_failures = 2 configured, a
-- target's real internal_health only converges after two consecutive
-- attempts, so requiring only 1 would let a readiness gate open before the
-- target's true state is actually known.
--
-- Deliberately a module function operating on shm (like get_target_list),
-- not a `checker:` instance method: the probe count must be readable from
-- any worker evaluating a readiness gate, not just whichever one created the
-- checker locally or holds the periodic-probe lock.
function _M.all_targets_probed(name, shm_name, min_attempts)
  min_attempts = min_attempts or 1
  local targets, err = _M.get_target_list(name, shm_name)
  if not targets then
    return nil, err
  end
  if #targets == 0 then
    return false
  end
  for _, target in ipairs(targets) do
    if (target.probe_count or 0) < min_attempts then
      return false
    end
  end
  return true
end


if TESTING then
  -- test-only hook: shorten the stale-target cleanup window so the periodic
  -- cleanup path can be exercised deterministically without waiting for the
  -- default CLEANUP_INTERVAL (CHECK_INTERVAL * 25).
  function _M._set_cleanup_interval(interval)
    CLEANUP_INTERVAL = interval
  end

  -- test-only hook: shorten the shm-vs-local-cache reconciliation cadence so
  -- the self-heal path (apache/apisix#13888) can be exercised deterministically
  -- without waiting for the default RECONCILE_INTERVAL.
  function _M._set_reconcile_interval(interval)
    RECONCILE_INTERVAL = interval
    last_reconcile_time = 0
  end
end


return _M
