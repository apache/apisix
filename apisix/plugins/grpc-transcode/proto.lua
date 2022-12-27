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
local core          = require("apisix.core")
local config_util   = require("apisix.core.config_util")
local pb            = require("pb")
local protoc        = require("protoc")
local pcall         = pcall
local ipairs        = ipairs
local decode_base64 = ngx.decode_base64


local protos
local lrucache_proto = core.lrucache.new({
    ttl = 300, count = 100
})

local proto_fake_file = "filename for loaded"

local function compile_proto_text(content)
    protoc.reload()
    local _p  = protoc.new()
    -- the loaded proto won't appears in _p.loaded without a file name after lua-protobuf=0.3.2,
    -- which means _p.loaded after _p:load(content) is always empty, so we can pass a fake file
    -- name to keep the code below unchanged, or we can create our own load function with returning
    -- the loaded DescriptorProto table additionally, see more details in
    -- https://github.com/apache/apisix/pull/4368
    local ok, res = pcall(_p.load, _p, content, proto_fake_file)
    if not ok then
        return nil, res
    end

    if not res or not _p.loaded then
        return nil, "failed to load proto content"
    end

    local compiled = _p.loaded

    local index = {}
    for _, s in ipairs(compiled[proto_fake_file].service or {}) do
        local method_index = {}
        for _, m in ipairs(s.method) do
            method_index[m.name] = m
        end

        index[compiled[proto_fake_file].package .. '.' .. s.name] = method_index
    end

    compiled[proto_fake_file].index = index

    return compiled
end


local function compile_proto_bin(content)
    content = decode_base64(content)
    if not content then
        return nil
    end

    -- pb.load doesn't return err
    local ok = pb.load(content)
    if not ok then
        return nil
    end

    local files = pb.decode("google.protobuf.FileDescriptorSet", content).file
    local index = {}
    for _, f in ipairs(files) do
        for _, s in ipairs(f.service or {}) do
            local method_index = {}
            for _, m in ipairs(s.method) do
                method_index[m.name] = m
            end

            index[f.package .. '.' .. s.name] = method_index
        end
    end

    local compiled = {}
    compiled[proto_fake_file] = {}
    compiled[proto_fake_file].index = index
    return compiled
end


local function compile_proto(content)
    -- clear pb state
    pb.state(nil)

    local compiled, err = compile_proto_text(content)
    if not compiled then
        compiled = compile_proto_bin(content)
        if not compiled then
            return nil, err
        end
    end

    -- fetch pb state
    compiled.pb_state = pb.state(nil)
    return compiled
end


local _M = {
    version = 0.1,
    compile_proto = compile_proto,
    proto_fake_file = proto_fake_file
}

local function create_proto_obj(proto_id)
    if protos.values == nil then
        return nil
    end

    local content
    for _, proto in config_util.iterate_values(protos.values) do
        if proto_id == proto.value.id then
            content = proto.value.content
            break
        end
    end

    if not content then
        return nil, "failed to find proto by id: " .. proto_id
    end

    return compile_proto(content)
end


function _M.fetch(proto_id)
    return lrucache_proto(proto_id, protos.conf_version,
                          create_proto_obj, proto_id)
end


function _M.protos()
    if not protos then
        return nil, nil
    end

    return protos.values, protos.conf_version
end


local grpc_status_proto = [[
    syntax = "proto3";

    package grpc_status;

    message Any {
      // A URL/resource name that uniquely identifies the type of the serialized
      // protocol buffer message. This string must contain at least
      // one "/" character. The last segment of the URL's path must represent
      // the fully qualified name of the type (as in
      // `path/google.protobuf.Duration`). The name should be in a canonical form
      // (e.g., leading "." is not accepted).
      //
      // In practice, teams usually precompile into the binary all types that they
      // expect it to use in the context of Any. However, for URLs which use the
      // scheme `http`, `https`, or no scheme, one can optionally set up a type
      // server that maps type URLs to message definitions as follows:
      //
      // * If no scheme is provided, `https` is assumed.
      // * An HTTP GET on the URL must yield a [google.protobuf.Type][]
      //   value in binary format, or produce an error.
      // * Applications are allowed to cache lookup results based on the
      //   URL, or have them precompiled into a binary to avoid any
      //   lookup. Therefore, binary compatibility needs to be preserved
      //   on changes to types. (Use versioned type names to manage
      //   breaking changes.)
      //
      // Note: this functionality is not currently available in the official
      // protobuf release, and it is not used for type URLs beginning with
      // type.googleapis.com.
      //
      // Schemes other than `http`, `https` (or the empty scheme) might be
      // used with implementation specific semantics.
      //
      string type_url = 1;

      // Must be a valid serialized protocol buffer of the above specified type.
      bytes value = 2;
    }

    // The `Status` type defines a logical error model that is suitable for
    // different programming environments, including REST APIs and RPC APIs. It is
    // used by [gRPC](https://github.com/grpc). Each `Status` message contains
    // three pieces of data: error code, error message, and error details.
    //
    // You can find out more about this error model and how to work with it in the
    // [API Design Guide](https://cloud.google.com/apis/design/errors).
    message ErrorStatus {
        // The status code, which should be an enum value of [google.rpc.Code][google.rpc.Code].
        int32 code = 1;

        // A developer-facing error message, which should be in English. Any
        // user-facing error message should be localized and sent in the
        // [google.rpc.Status.details][google.rpc.Status.details] field, or localized by the client.
        string message = 2;

        // A list of messages that carry the error details.  There is a common set of
        // message types for APIs to use.
        repeated Any details = 3;
    }
]]


local status_pb_state
local function init_status_pb_state()
    if not status_pb_state then
        -- clear current pb state
        local old_pb_state = pb.state(nil)

        -- initialize protoc compiler
        protoc.reload()
        local status_protoc = protoc.new()
        -- do not use loadfile here, it can not load the proto file when using a relative address
        -- after luarocks install apisix
        local ok, err = status_protoc:load(grpc_status_proto, "grpc_status.proto")
        if not ok then
            status_protoc:reset()
            pb.state(old_pb_state)
            return "failed to load grpc status protocol: " .. err
        end

        status_pb_state = pb.state(old_pb_state)
    end
end


function _M.fetch_status_pb_state()
    return status_pb_state
end


function _M.init()
    local err
    protos, err = core.config.new("/protos", {
        automatic = true,
        item_schema = core.schema.proto
    })
    if not protos then
        core.log.error("failed to create etcd instance for fetching protos: ",
                       err)
        return
    end

    if not status_pb_state then
        err = init_status_pb_state()
        if err then
            core.log.error("failed to init grpc status proto: ",
                            err)
            return
        end
    end
end

function _M.destroy()
    if protos then
        protos:close()
    end
end

return _M
