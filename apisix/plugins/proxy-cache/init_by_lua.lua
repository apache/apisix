-- Before
ngx.config.debug = true

-- extra_init_by_lua_start
local mock_service = require("spec.plugins.proxy-cache.mock_service")
mock_service:start()

-- extra_init_by_lua
local cjson = require("cjson")
cjson.encode_empty_table_as_object(false)

-- After
-- extra_init_by_lua_start
local mock_service = require("spec.plugins.proxy-cache.mock_service")
mock_service:start()

-- extra_init_by_lua
local function init()
  local cjson = require("cjson")
  cjson.encode_empty_table_as_object(false)
end

ngx.on_abort(init)
ngx.config.debug = true
