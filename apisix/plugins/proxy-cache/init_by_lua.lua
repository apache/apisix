-- Before
ngx.config.debug = true

-- extra_init_by_lua_start
local mock_service = require("spec.plugins.proxy-cache.mock_service")
mock_service:start()

-- extra_init_by_lua
local cjson = require("cjson")
cjson.encode_empty_table_as_object(false)

-- After
local function init()
  local mock_service = require("spec.plugins.proxy-cache.mock_service")
  mock_service:start()

  local cjson = require("cjson")
  cjson.encode_empty_table_as_object(false)
end

ngx.config.debug = true
ngx.on_abort(init)
