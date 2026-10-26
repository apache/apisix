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

-- Per-process OpenResty internals: Lua timers, connection slots and Lua VM
-- memory. These values only exist inside the process they describe, while the
-- exposition is rendered by a single process, so every process writes its own
-- gauges into the shared metric dict from a timer, and the process rendering
-- the exposition refreshes its own values right before it does.
local core          = require("apisix.core")
local ffi           = require("ffi")
local process       = require("ngx.process")
local C             = ffi.C
local ngx           = ngx
local timer_at      = ngx.timer.at
local collectgarbage = collectgarbage
local tonumber      = tonumber
local tostring      = tostring
local pcall         = pcall
local ipairs        = ipairs
local pairs         = pairs
local select        = select


-- nginx 1.29.7 appends spare slots to ngx_log_t in --with-compat builds
local log_spare = ""
if ngx.config.nginx_version >= 1029007
   and ngx.config.nginx_configure():find("--with-compat", 1, true)
then
    log_spare = "uint64_t spare[5];"
end


-- The prefix of struct ngx_cycle_s up to write_events, as laid out by the
-- supported runtimes (nginx 1.21.4 to 1.31.x); the self check in
-- check_cycle_layout() is what keeps a future change from turning into a
-- wrong number.
ffi.cdef([[
typedef struct {
    uintptr_t       log_level;
    void           *file;
    uintptr_t       connection;
    long            disk_full_time;
    void           *handler;
    void           *data;
    void           *writer;
    void           *wdata;
    char           *action;
    void           *next;
    ]] .. log_spare .. [[
} apisix_prom_ngx_log_t;

typedef struct {
    void           *elts;
    uintptr_t       nelts;
    size_t          size;
    uintptr_t       nalloc;
    void           *pool;
} apisix_prom_ngx_array_t;

typedef struct {
    void           *elts;
    uintptr_t       nelts;
    void           *next;
} apisix_prom_ngx_list_part_t;

typedef struct {
    void                        *last;
    apisix_prom_ngx_list_part_t  part;
    size_t                       size;
    uintptr_t                    nalloc;
    void                        *pool;
} apisix_prom_ngx_list_t;

typedef struct {
    uintptr_t       key;
    void           *left;
    void           *right;
    void           *parent;
    unsigned char   color;
    unsigned char   data;
} apisix_prom_ngx_rbtree_node_t;

typedef struct {
    void           *root;
    void           *sentinel;
    void           *insert;
} apisix_prom_ngx_rbtree_t;

typedef struct {
    void           *data;
    void           *read;
    void           *write;
} apisix_prom_ngx_connection_head_t;

typedef struct {
    void                           *conf_ctx;
    void                           *pool;
    void                           *log;
    apisix_prom_ngx_log_t           new_log;
    uintptr_t                       log_use_stderr;
    void                           *files;
    void                           *free_connections;
    uintptr_t                       free_connection_n;
    void                           *modules;
    uintptr_t                       modules_n;
    uintptr_t                       modules_used;
    void                           *reusable_connections_queue[2];
    uintptr_t                       reusable_connections_n;
    long                            connections_reuse_time;
    apisix_prom_ngx_array_t         listening;
    apisix_prom_ngx_array_t         paths;
    apisix_prom_ngx_array_t         config_dump;
    apisix_prom_ngx_rbtree_t        config_dump_rbtree;
    apisix_prom_ngx_rbtree_node_t   config_dump_sentinel;
    apisix_prom_ngx_list_t          open_files;
    apisix_prom_ngx_list_t          shared_memory;
    uintptr_t                       connection_n;
    uintptr_t                       files_n;
    apisix_prom_ngx_connection_head_t *connections;
    void                           *read_events;
    void                           *write_events;
} apisix_prom_ngx_cycle_t;

extern apisix_prom_ngx_cycle_t *ngx_cycle;
]])


-- nginx's own defaults for lua_max_running_timers / lua_max_pending_timers,
-- in effect when the configuration leaves them out
local DEFAULT_MAX_RUNNING_TIMERS = 256
local DEFAULT_MAX_PENDING_TIMERS = 1024
local DEFAULT_INTERVAL = 15

-- Shared by every process, so a layout mismatch found by one worker keeps the
-- connection gauges out of the exposition everywhere, including the
-- privileged agent, whose connection count cannot be checked against config.
local CONNECTIONS_VERDICT_KEY = "process_metrics:connections_readable"

local _M = {}

local gauges
local registry
local dict
local process_label
local no_extra_labels = {}
local extra_label_names = no_extra_labels
local extra_label_values
local subsystem = ngx.config.subsystem
local verdict_logged = false

local timer_running = false
local stopped = true
local interval = DEFAULT_INTERVAL
local retired_cleanups = 0


local function get_process_label()
    if process.type() == "privileged agent" then
        return "privileged-agent"
    end

    return "worker-" .. tostring(ngx.worker.id() or 0)
end


-- The CLI refuses to start without nginx_config, but a forced re-read of
-- config.yaml at runtime (plugin reload) can still drop it: `nginx_config: ~`
-- deletes the default table while merging.
local function nginx_config()
    return core.config.local_conf().nginx_config or {}
end


local function timers_max()
    local conf = nginx_config()
    return conf.max_running_timers or DEFAULT_MAX_RUNNING_TIMERS,
           conf.max_pending_timers or DEFAULT_MAX_PENDING_TIMERS
end


local function read_cycle()
    local cycle = C.ngx_cycle
    local connection_n = tonumber(cycle.connection_n)
    local free_n = tonumber(cycle.free_connection_n)
    if connection_n == 0 or free_n > connection_n then
        return nil
    end

    return connection_n, free_n
end


local function check_cycle_layout()
    local ok, connection_n = pcall(read_cycle)
    if not ok or not connection_n then
        return false, "unexpected nginx cycle layout"
    end

    local event = nginx_config().event
    local expected = event and tonumber(event.worker_connections)
    if connection_n ~= expected then
        return false, "worker connection slots read as " .. tostring(connection_n)
                      .. ", but worker_connections is " .. tostring(expected)
    end

    -- every connection slot is wired to its own pair of events at startup, so
    -- this pins down the offsets right after connection_n as well. Only follow
    -- the pointer once connection_n matched: a bad one crashes the worker.
    local cycle = C.ngx_cycle
    local conns = cycle.connections
    if conns == nil
       or conns[0].read ~= cycle.read_events or conns[0].write ~= cycle.write_events
    then
        return false, "unexpected nginx cycle layout"
    end

    return true
end


-- Only a worker can tell whether the numbers read through FFI are right: its
-- connection slots must match worker_connections from the configuration.
local function connections_readable()
    local readable = dict:get(CONNECTIONS_VERDICT_KEY)
    if readable ~= nil then
        return readable
    end

    if process.type() == "privileged agent" then
        -- no worker has checked yet
        return false
    end

    local ok, err = check_cycle_layout()
    dict:set(CONNECTIONS_VERDICT_KEY, ok)
    if not ok then
        gauges.connections:reset()
        gauges.connections_max:reset()
        if not verdict_logged then
            verdict_logged = true
            core.log.warn("process connection metrics are disabled: ", err)
        end
    end

    return ok
end


local function with_extra_labels(labels)
    for _, name in ipairs(extra_label_names) do
        labels[#labels + 1] = name
    end
    return labels
end


local function label_values(extra, ...)
    local values = {...}
    local n = select("#", ...)
    for i, value in ipairs(extra) do
        values[n + i] = value
    end
    return values
end


-- extra_labels, when given, appends the same labels to every gauge here:
-- {names = {...}, values = function() return {...} end}
function _M.init(prometheus_registry, extra_labels)
    registry = prometheus_registry
    dict = registry.dict
    if extra_labels then
        extra_label_names = extra_labels.names
        extra_label_values = extra_labels.values
    end

    gauges = {
        timers = registry:gauge("nginx_timers",
            "Number of Lua timers per process and subsystem, by state",
            with_extra_labels({"process", "subsystem", "state"})),
        timers_max = registry:gauge("nginx_timers_max",
            "Configured maximum number of Lua timers per process, by state",
            with_extra_labels({"state"})),
        connections = registry:gauge("nginx_process_connections",
            "Number of connection slots in use per nginx process",
            with_extra_labels({"process"})),
        connections_max = registry:gauge("nginx_process_connections_max",
            "Number of connection slots per nginx process",
            with_extra_labels({"process"})),
        lua_memory = registry:gauge("nginx_lua_memory_bytes",
            "Memory allocated by the Lua VM per process and subsystem",
            with_extra_labels({"process", "subsystem"})),
    }

    -- the verdict describes the binary and the configuration of the processes
    -- starting now, so each worker checks again rather than trusting the one
    -- left behind in the shared dict by a reload
    if subsystem == "http" and process.type() ~= "privileged agent" then
        dict:delete(CONNECTIONS_VERDICT_KEY)
    end
end


local function report()
    process_label = process_label or get_process_label()
    local extra = extra_label_values and extra_label_values() or no_extra_labels

    local timers = gauges.timers
    timers:set(ngx.timer.running_count(),
               label_values(extra, process_label, subsystem, "running"))
    timers:set(ngx.timer.pending_count(),
               label_values(extra, process_label, subsystem, "pending"))

    gauges.lua_memory:set(collectgarbage("count") * 1024,
                          label_values(extra, process_label, subsystem))

    -- the remaining values are per process rather than per Lua VM, so only
    -- the http VM reports them; it is present in every process that exports
    if subsystem ~= "http" then
        return
    end

    local max_running, max_pending = timers_max()
    gauges.timers_max:set(max_running, label_values(extra, "running"))
    gauges.timers_max:set(max_pending, label_values(extra, "pending"))

    if not connections_readable() then
        return
    end

    local connection_n, free_n = read_cycle()
    if not connection_n then
        return
    end

    gauges.connections:set(connection_n - free_n, label_values(extra, process_label))
    gauges.connections_max:set(connection_n, label_values(extra, process_label))
end


-- Writes this process's values now. A failure here is logged rather than
-- raised, so it can never cost the caller the rest of the exposition.
function _M.refresh()
    if not gauges then
        return
    end

    local ok, err = pcall(report)
    if not ok then
        core.log.error("failed to report process metrics: ", err)
    end
end


-- A reload with fewer workers leaves the series of the workers that are gone
-- in the shared dict, where nothing overwrites them any more. Expiring them is
-- not an option: some nginx-lua-prometheus versions do not renew the key index
-- of a series that is set again, so a live series would expire as well.
local function remove_retired_workers()
    local names = {}
    for _, gauge in pairs(gauges) do
        names[gauge.name] = true
    end

    local worker_count = ngx.worker.count()
    local key_index = registry.key_index
    for _, key in ipairs(key_index:list()) do
        local name = key:match("^([^{]+){")
        local id = name and names[name] and key:match('process="worker%-(%d+)"')
        if id and tonumber(id) >= worker_count then
            key_index:remove(key)
            dict:delete(key)
        end
    end
end


local function tick(premature)
    if premature or stopped then
        timer_running = false
        if stopped then
            core.log.info("process metrics stopped")
        end
        return
    end

    if retired_cleanups > 0 then
        retired_cleanups = retired_cleanups - 1
        local ok, err = pcall(remove_retired_workers)
        if not ok then
            core.log.error("failed to remove the metrics of retired workers: ", err)
        end
    end

    _M.refresh()

    local ok, err = timer_at(interval, tick)
    if not ok then
        timer_running = false
        core.log.error("failed to schedule process metrics: ", err)
    end
end


-- Idempotent: calling it again while reporting only updates the interval.
function _M.start(report_interval)
    if not gauges then
        return
    end

    interval = report_interval or DEFAULT_INTERVAL
    stopped = false

    -- one process is enough, and the privileged agent always exists. The second
    -- pass, one interval later, catches a sample that an exiting worker was
    -- still writing while the first one ran.
    if subsystem == "http" and process.type() == "privileged agent" then
        retired_cleanups = 2
    end

    if timer_running then
        return
    end

    timer_running = true
    local ok, err = timer_at(0, tick)
    if not ok then
        timer_running = false
        core.log.error("failed to start process metrics: ", err)
        return
    end

    core.log.info("process metrics started, reporting every ", interval, "s")
end


-- The pending timer sees this when it fires and does not schedule another.
function _M.stop()
    stopped = true
end


return _M
