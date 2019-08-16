local pb = require("pb")
local json
if not os.getenv("LUAUNIT") then
  json = require("cjson")
end

local _M = {}

_M.file_exists = function(file)
  local fp = io.open(file, "r")
  if fp then
    fp:close()
    return true
  end
  return false
end

_M.find_method = function(proto, service, method)
  local protos = proto.get_loaded_proto()
  for k, loaded in pairs(protos) do
    local package = loaded.package
    for _, s in ipairs(loaded.service or {}) do
      if ("%s.%s"):format(package, s.name) == service then
        for _, m in ipairs(s.method) do
          if m.name == method then
            return m
          end
        end
      end
    end
  end

  return nil
end

local function get_from_request(name, kind)
  local request_table
  if ngx.req.get_method() == "POST" then
    if string.find(ngx.req.get_headers()["Content-Type"] or "", "application/json") then
      request_table = json.decode(ngx.req.get_body_data())
    else
      request_table = ngx.req.get_post_args()
    end
  else
    request_table = ngx.req.get_uri_args()
  end
  local prefix = kind:sub(1, 3)
  if prefix == "str" then
    return request_table[name] or nul
  elseif prefix == "int" then
    if request_table[name] then
      return tonumber(request_table[name])
    else
      return nil
    end
  end
  return nil
end

_M.map_message = function(field, default_values)
  if not pb.type(field) then
    return nil, ("Field %s is not defined"):format(field)
  end

  local request = {}
  for name, _, field_type in pb.fields(field) do
    if field_type:sub(1, 1) == "." then
      sub, err = _M.map_message(field_type, default_values)
      if err then
        return nil, err
      end
      request[name] = sub
    else
      request[name] = get_from_request(name, field_type) or default_values[name] or nil
    end
  end
  return request, nil
end

return _M
