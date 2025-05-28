local core = require("apisix.core")
local http = require('resty.http')
local utils = require("apisix.discovery.nacos.utils")

local ngx_timer_at = ngx.timer.at
local math_random  = math.random
local nacos_dict = ngx.shared.nacos

local NACOS_LOGIN_PATH = "/auth/login"
local NACOS_INSTANCE_PATH = "ns/instance/list"

local _M = {}


local function _request(method, uri, params, headers, body, options)
    local url = uri
    if params ~= nil and params ~= {} then
        url = uri .. "?" .. utils.generate_request_params(params)
    end
    core.log.warn("final uri: ", url)
    local httpc = http.new()
    local timeout = options and options.timeout or {}
    local connect_timeout = timeout.connect and timeout.connect * 1000 or 2000
    local read_timeout = timeout.read and timeout.read * 1000 or 2000
    local write_timeout = timeout.write and timeout.write * 1000 or 5000

    httpc:set_timeouts(connect_timeout, read_timeout, write_timeout )
    local res, err = httpc:request_uri(url, {
        method = method,
        headers = headers,
        body = body,
        ssl_verify = false,
    })

    if not res then
        return nil, err
    end

    if not res.body or res.status ~= 200 then
        return nil, 'status = ' .. res.status
    end

    core.log.info("request to nacos, uri: ", uri, "response: ", res.body)

    local data, err = core.json.decode(res.body)
    if not data then
        return nil, err
    end

    return data
end


local function request_login(self, username, password)
    local params = {
       ["username"] = username,
       ["password"] = password,
    }

    local hosts = self.config.hosts
    local uri = hosts[math_random(#hosts)] .. self.config.prefix .. NACOS_LOGIN_PATH
    local headers = {
        ["Content-Type"] ="application/x-www-form-urlencoded"
    }

    local resp, err = _request("POST", uri, nil, headers, utils.generate_request_params(params), {timeout=self.config.timeout})
    if not resp then
        core.log.error("failed to fetch token from nacos, uri: ", uri, " err: ", err)
        return ""
    end

    return resp.accessToken
end

local inspect = require("inspect")
local function request_instance_list(self, params)
    local hosts = self.config.hosts
		core.log.warn("FIRST CONCATENATAE ", inspect(hosts[math_random(#hosts)]))
    local uri = hosts[math_random(#hosts)] .. self.config.prefix .. NACOS_INSTANCE_PATH

    local resp, err = _request("GET", uri, params)
    if not resp then
        core.log.error("failed to fetch instances list from nacos, uri: ", uri, " err: ", err)
        return {}
    end

    return resp.hosts or {}
end

local function fetch_instances(self, serv)
    local config = self.config

    local params = {
        ["namespaceId"] = serv.namespace_id or "",
        ["groupName"] = serv.group_name or "DEFAULT_GROUP",
        ["serviceName"] = serv.name,
        ["healthyOnly"] = "true"
    }

    local auth = config.auth or {}
    if (auth.username and auth.username ~= "") and (auth.password and auth.password ~= "") then
       local token = request_login(self, auth.username, auth.password)
       params["accessToken"] = token
    end

    if auth.token and auth.token ~= "" then
        params["accessToken"] = auth.token
    end

    if (auth.access_key and auth.access_key ~= "") and (auth.secret_key and auth.secret_key ~= "") then
       local ak, data, signature = utils.generate_signature(serv.group_name, serv.name, auth.access_key, auth.secret_key)
       params["ak"] = ak
       params["data"] = data
       params["signature"] = signature
    end

    local instances = request_instance_list(self, params)
    local nodes = {}
    for _, instance in ipairs(instances) do
        local node = {
            host = instance.ip,
            port = instance.port,
            weight = instance.weight or self.config.default_weight,
            metadata = instance.metadata,
        }

        core.table.insert(nodes, node)
    end

    return nodes
end


local function fetch_full_registry(self)
    return function (premature)
        if premature then
            return
        end

        local config = self.config
        local services_in_use = utils.get_nacos_services(config.id)
        for _, serv in ipairs(services_in_use) do
            if self.stop_flag then
                core.log.error("nacos client is exited, id: ", config.id)
                return
            end

            local nodes = self:fetch_instances(serv)
            if #nodes > 0 then
                local content = core.json.encode(nodes)
                nacos_dict:set(serv.service_name, content, self.config.fetch_interval * 10)
             end
        end

        ngx_timer_at(self.config.fetch_interval, self:fetch_full_registry())
    end
end


local function stop(self)
    self.stop_flag = true

    if self.checker then
        self.checker:clear()
    end
end


local function start(self)
    ngx_timer_at(0, self:fetch_full_registry())
end


function _M.new(config)
    local version = ngx.md5(core.json.encode(config, true))

    local client = {
        id = config.id,
        version = version,
        config = config,
        stop_flag = false,

        start = start,
        stop = stop,
        fetch_instances = fetch_instances,
        fetch_full_registry = fetch_full_registry,
    }

    if config.check then
        local health_check = require("resty.healthcheck")
        local checker = health_check.new({
            name = config.id,
            shm_name = "nacos",
            checks = config.check
        })

        local ok, err = checker:add_target(config.check.active.host, config.check.active.port, nil, false)
        if not ok then
            core.log.error("failed to add health check target", core.json.encode(config), " err: ", err)
        else
            core.log.info("success to add health checker, id ", config.id, " host ", config.check.active.host, " port ", config.check.active.port)
            client.checker = checker
        end
    end

    return client
end

return _M
