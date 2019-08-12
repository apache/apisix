local protoc = require("protoc")
local util = require("apisix.plugins.grpc-proxy.util")

local _M = {}

_M.new = function(proto_id)
  local _p = protoc.new()
  --todo read proto content from etcd by id
  local ppp = [[
           syntax = "proto3";

  option java_multiple_files = true;
  option java_package = "io.grpc.examples.helloworld";
  option java_outer_classname = "HelloWorldProto";

  package helloworld;

  // The greeting service definition.
  service Greeter {
    // Sends a greeting
    rpc SayHello (HelloRequest) returns (HelloReply) {}
  }

  // The request message containing the user's name.
  message HelloRequest {
    string name = 1;
  }

  // The response message containing the greetings
  message HelloReply {
    string message = 1;
  } ]]

  _p:load(ppp)

  local instance = {}
  instance.get_loaded_proto = function()
    return _p.loaded
  end
  return instance
end

return _M
