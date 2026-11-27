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

-- Run from the repository root with Lua or LuaJIT.
local core = {
    schema = {plugin_injected_schema = {['$comment'] = 'injected'}},
    log = {error = function() end},
}
package.loaded['apisix.core'] = core
package.loaded['lfs'] = {}
local registry = require('apisix.plugin_registry')

local base = [[return {version = 0.1, priority = 1,
    schema = {type = 'object', properties = {enabled = {type = 'boolean'}}}}]]
local candidate = assert(registry.compile('http~demo', base))
assert(registry.split('stream~demo') == 'stream')
assert(not registry.split('http~../demo'))
assert(not registry.split('http~demo\n'))
assert(not registry.valid_version('bundled'))
assert(not registry.compile('http~demo', string.char(27) .. 'Lua'))
assert(not registry.compile('http~demo', 'return {}'))
assert(not registry.compile('http~demo', 'error("invalid module")'))
assert(registry.compatible(candidate, assert(registry.compile('http~demo', base))))
local changed = assert(registry.compile('http~demo', base:gsub('boolean', 'number')))
assert(not registry.compatible(candidate, changed))
local bare = {schema = {type = 'object'}}
local injected = {schema = {type = 'object', properties = {_meta = {}}, ['$comment'] = 'injected'}}
assert(registry.compatible(injected, bare), 'ignore loader-injected properties')
assert(registry.compatible(bare, injected), 'ignore loader-injected properties in either direction')
assert(not registry.compatible(candidate, bare), 'still reject removal of application properties')

local applied = {}
local function swap(item)
    if item.version == 'broken' then
        return nil, 'initialization failed'
    end
    applied[#applied + 1] = item.version
    return true
end
local reconcile = registry.reconciler(swap)
reconcile({id = 'http~demo', version = 'v1', source = base})
reconcile({id = 'http~demo', version = 'v1', source = base})
reconcile({id = 'http~demo', version = 'broken', source = base})
assert(#applied == 1 and registry.status('http~demo').effective == 'v1')
assert(registry.status('http~demo').error == 'initialization failed')
reconcile({id = 'http~demo', version = 'bundled'})
assert(applied[2] == 'bundled' and not registry.status('http~demo').error)
print('plugin registry contracts passed')

-- Verify publication compares the exact draft, version and active revisions.
local id = 'http~demo'
local draft_key = registry.draft_path .. '/' .. id
local version_key = registry.version_path .. '/' .. id .. '/v2'
local active_key = registry.active_path .. '/' .. id
local release_key = string.rep('a', 32)
local nodes = {
    [draft_key] = {value = {source = base}, modifiedIndex = '12'},
    [active_key] = {value = {version = 'v1', source = base}, modifiedIndex = '9'},
}
local writes = 0
local draft_changed = true
core.config = {local_conf = function()
    return {
        deployment = {config_provider = 'etcd', admin = {admin_key = {}}},
        plugin_attr = {plugin_registry = {enabled = true, release_key = release_key}},
    }
end}
core.request = {header = function() return release_key end}
ngx = {time = function() return 100 end}
package.loaded.bit = {bor = function() return 0 end, bxor = function() return 0 end}
package.loaded['apisix.plugin'] = {get = function() return candidate end}
core.etcd = {
    get = function(key)
        if nodes[key] then
            return {status = 200, body = {node = nodes[key]}}
        end
        return {status = 404}
    end,
    atomic_set = function(key, value)
        nodes[key] = {value = value, modifiedIndex = '13'}
        writes = writes + 1
        return {headers = {['X-Etcd-Index'] = '13'}}
    end,
    get_etcd_cli = function()
        return {txn = function(_, conditions, updates)
            assert(#conditions == 3 and #updates == 2)
            if draft_changed then
                nodes[draft_key].modifiedIndex = '13'
            end
            local compared = {}
            for _, condition in ipairs(conditions) do
                assert(condition.key:sub(1, 5) == '/test')
                assert(condition.target == 'MOD' and condition.result == 'EQUAL')
                compared[condition.key:sub(6)] = condition.mod_revision
            end
            assert(compared[active_key] == '9' and compared[version_key] == '0')
            if compared[draft_key] ~= nodes[draft_key].modifiedIndex then
                return {status = 200, body = {succeeded = false}}
            end
            for _, update in ipairs(updates) do
                local put = update.requestPut
                assert(put.key:sub(1, 5) == '/test')
                nodes[put.key:sub(6)] = {value = put.value, modifiedIndex = '14'}
                writes = writes + 1
            end
            return {status = 200, body = {succeeded = true, header = {revision = '14'}}}
        end}, '/test'
    end,
}
local admin = require('apisix.admin.plugin_registry')
local publish = {action = 'publish', version = 'v2', active_revision = '9', draft_revision = '12'}
assert(admin:post(id, publish) == 409, 'a concurrently modified draft must reject publication')
assert(not nodes[version_key] and nodes[active_key].value.version == 'v1' and writes == 0)
draft_changed = false
publish.draft_revision = '13'
local code, result = admin:post(id, publish)
assert(code == 200 and result.revision == '14' and writes == 2)
assert(nodes[version_key].value.source == base and nodes[active_key].value.version == 'v2')
print('plugin registry publication transaction passed')
