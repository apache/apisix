local core        = require("apisix.core")
local ngx         = ngx
local plugin_name = "csrf"
local ngx_encode_base64 = ngx.encode_base64
local ngx_decode_base64 = ngx.decode_base64
local ck = require "resty.cookie"
local math = math

local lrucache = core.lrucache.new({
    type = "plugin",
})

local schema = {
	type = "object",
	properties = {
		key = {
			description = "use to generate csrf token",
			type = "string",
		},
		expires = {
			description = "expires time for csrf token",
			type = "integer",
			default = 7200
		},
    name = {
      description = "the csrf token name",
      type = "string",
      default = "apisix_csrf_token"
    }
	},
  required = {"key"}
}

local _M = {
  version = 0.1,
  priority = 3500,
  name = plugin_name,
  schema = schema,
}

function _M.check_schema(conf)
  return core.schema.check(schema, conf)
end

local function gen_sign(random, expires, key)
  local resty_sha256 = require "resty.sha256"
  local str = require "resty.string"

  local sha256 = resty_sha256:new()

  local sign = {
    random = random,
    expires = expires,
    key = key,
  }

  sha256:update(core.json.encode(sign))
  local digest = sha256:final()

  return ngx_encode_base64(digest)
end

local function gen_csrf_token(conf)
  local random = math.random();

  local sign = gen_sign(random, conf.expires, conf.key)

  local token = {
    random = random,
    expires = conf.expires,
    sign = sign,
  }

  local cookie = ngx_encode_base64(core.json.encode(token))
  return cookie
end

local function check_csrf_token(conf, ctx, token)
  local _token = ngx_decode_base64(token)

  local _token_table, err = core.json.decode(_token)
  if err then
    core.log.error("decode token error: ", err)
    return false
  end

  local random = _token_table["random"]
  if not random then
    core.log.warn("no random in token")
    return false
  end

  local expires = _token_table["expires"]
  if not expires then
    core.log.warn("no expires in token")
    return false
  end

  local sign = gen_sign(random, expires, conf.key)

  if _token_table["sign"] ~= sign then
    return false
  end

  return true
end

function _M.access(conf, ctx)
  local method = ngx.var.request_method
  if method == 'GET' then
    return
  end

  local token = core.request.header(ctx, conf.name)
  if not token then
    return 401, {error_msg = "no csrf token in request header"}
  end

  local cookie, err = ck:new()
  if not cookie then
    return nil, err
  end
  local field_cookie, err = cookie:get(conf.name)
  if not field_cookie then
    return 401, {error_msg = "no csrf cookie"}
  end
  if err then
    core.log.error(err)
    return 500, {error_msg = "read csrf cookie failed"}
  end

  if token ~= field_cookie then
    return 401, {error_msg = "csrf token mismatch"}
  end

  local result = check_csrf_token(conf, ctx, token)
  if not result then
    return 401, {error_msg = "Failed to verify the csrf token signature"}
  end
end

function _M.header_filter(conf, ctx)
  local method = ngx.var.request_method
  if method == 'GET' then
    local csrf_token = gen_csrf_token(conf)
    core.response.add_header("Set-Cookie", {conf.name.."="..csrf_token..";path=/;Expires="..ngx.cookie_time(ngx.time() + conf.expires)})
  end
end

return _M
