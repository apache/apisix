local core = require("apisix.core")

local _M = {}


local function test_depth_more_than_10()
  _M.a = {
    a = {
      a = {
        a = {
          a = {
            a = {
              a = {
                a = {
                  a = {
                    a = {
                      "should not be counted"
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
end

--- test function creates adds 1.
local function test()
  core.table.insert(_M, "xyz")
end

--- test_circular function creates a circular reference and adds 5 objects
local function test_circular()
  local a = {}
  local b = { a }
  a.b = b
  a.c = b
  _M.a = a
  _M.b = b

  _M.func = function() end

  _M.i = 1
  _M.d = {
    a = a,
  }
end

_M.test = test
_M.test_circular = test_circular
_M.test_depth_more_than_10 = test_depth_more_than_10
return _M
