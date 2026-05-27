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

--- test function adds 1 entry.
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
