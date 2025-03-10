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
local plugin_name = "api-breaker"
local ngx = ngx
local math = math
local error = error
local ipairs = ipairs


local auth_item_schema = {
  type = "object",
  patternProperties = {
      ["^[a-zA-Z0-9._-]+$"] = {
          type = "string"
      }
  }
}


local auth_schema = {
  type = "object",
  patternProperties = {
      header = auth_item_schema,
      query = auth_item_schema
  },
  additionalProperties = false
}


local model_options_schema = {
  description = "Key/value settings for the model",
  type = "object",
  properties = {
      model = {
          type = "string",
          description = "Model to execute."
      }
  },
  additionalProperties = true
}


local schema = {
  type = "object",
  properties = {
      prompt = {
          type = "string",
          description = "The prompt to rewrite client request."
      },
      provider = {
          type = "string",
          description = "Name of the AI service provider.",
          enum = {"openai", "openai-compatible", "deepseek"} -- add more providers later
      },
      auth = auth_schema,
      options = model_options_schema,
      timeout = {
          type = "integer",
          minimum = 1,
          maximum = 60000,
          default = 30000,
          description = "timeout in milliseconds",
      },
      keepalive = {type = "boolean", default = true},
      keepalive_pool = {type = "integer", minimum = 1, default = 30},
      ssl_verify = {type = "boolean", default = true },
      override = {
          type = "object",
          properties = {
              endpoint = {
                  type = "string",
                  description = "To be specified to override the endpoint of the AI service provider.",
              },
          },
      },
  },
  required = {"prompt", "provider", "auth"}
}


local _M = {
    version = 0.1,
    name = plugin_name,
    priority = 1005,
    schema = schema,
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


return _M
