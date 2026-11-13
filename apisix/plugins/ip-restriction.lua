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
local base = require("apisix.plugins.ip-restriction.init")


-- avoid unexpected data sharing
local ip_restriction = core.table.clone(base)


function ip_restriction.rewrite(conf, ctx)
    if conf.phase == "rewrite" then
        -- remember the conf, so the access phase does not check it twice
        local checked = ctx._ip_restriction_checked
        if not checked then
            checked = {}
            ctx._ip_restriction_checked = checked
        end
        checked[conf] = true
        return base.restrict(conf, ctx)
    end
end


-- Also the fallback for a "rewrite" conf that did not run in the rewrite phase,
-- such as a consumer conf merged into the route after authentication.
function ip_restriction.access(conf, ctx)
    local checked = ctx._ip_restriction_checked
    if not (checked and checked[conf]) then
        return base.restrict(conf, ctx)
    end
end


return ip_restriction
