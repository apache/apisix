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
local digest = require("resty.openssl.digest")

local DS = "http://www.w3.org/2000/09/xmldsig#"

local ALGORITHMS = {
    ["rsa-sha1"] = {
        digest = "sha1",
        digest_uri = DS .. "sha1",
        signature_uri = DS .. "rsa-sha1",
    },
    ["rsa-sha256"] = {
        digest = "sha256",
        digest_uri = "http://www.w3.org/2001/04/xmlenc#sha256",
        signature_uri = "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256",
    },
}

local _M = {}


function _M.get(name)
    return ALGORITHMS[name]
end


function _M.hash(value, algorithm)
    local context, err = digest.new(algorithm.digest)
    if not context then
        return nil, err
    end
    local ok, update_err = context:update(value)
    if not ok then
        return nil, update_err
    end
    return context:final()
end


return _M