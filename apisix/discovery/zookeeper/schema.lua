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

return {
    type = "object",
    properties = {
        -- ZooKeeper Cluster Addresses (separated by commas for multiple addresses)
        connect_string = {
            type = "string",
            default = "127.0.0.1:2181"
        },
        -- ZooKeeper Session Timeout (milliseconds)
        session_timeout = {
            type = "integer",
            minimum = 1000,
            default = 30000
        },
        -- ZooKeeper Connect Timeout (milliseconds)
        connect_timeout = {
            type = "integer",
            minimum = 1000,
            default = 5000
        },
        -- Service Discovery Root Path
        root_path = {
            type = "string",
            default = "/apisix/discovery/zk"
        },
        -- Instance Fetch Interval (seconds)
        fetch_interval = {
            type = "integer",
            minimum = 1,
            default = 10
        },
        -- The default weight value for service instances that do not specify a weight in ZooKeeper.
        -- It is used for load balancing (higher weight means more traffic).
        -- Default value is 100, and the value range is 1-500.
        weight = {
            type = "integer",
            minimum = 1,
            default = 100
        },
        -- ZooKeeper Authentication Information (digest: username:password):
        -- Digest authentication credentials for accessing ZooKeeper cluster.
        -- Format requirement: "digest:{username}:{password}".
        -- Leave empty to disable authentication (not recommended for production).
        auth = {
            type = "object",
            properties = {
                type = {type = "string", enum = {"digest"}, default = "digest"},
                creds = {type = "string"}  -- digest: username:password
            }
        },
        -- Cache Expiration Time (seconds):
        -- The time after which service instance cache becomes expired.
        -- Default value is 60 seconds
        cache_ttl = {
            type = "integer",
            minimum = 1,
            default = 60
        }
    },
    required = {},
    additionalProperties = false
}
