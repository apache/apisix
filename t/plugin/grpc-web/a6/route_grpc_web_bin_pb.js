/*
 * Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements.  See the NOTICE file distributed with
 * this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0
 * (the "License"); you may not use this file except in compliance with
 * the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

const grpc = {};
grpc.web = require('grpc-web');

const proto = {};
proto.a6 = require('./route_pb.js');

/**
 * @param {string} hostname
 * @param {?Object} credentials
 * @param {?grpc.web.ClientOptions} options
 * @constructor
 * @struct
 * @final
 */
proto.a6.RouteServiceClient =
    function(hostname, credentials, options) {
  if (!options) options = {};
  options.format = 'binary';

  /**
   * @private @const {!grpc.web.GrpcWebClientBase} The client
   */
  this.client_ = new grpc.web.GrpcWebClientBase(options);

  /**
   * @private @const {string} The hostname
   */
  this.hostname_ = hostname;

};


/**
 * @param {string} hostname
 * @param {?Object} credentials
 * @param {?grpc.web.ClientOptions} options
 * @constructor
 * @struct
 * @final
 */
proto.a6.RouteServicePromiseClient =
    function(hostname, credentials, options) {
  if (!options) options = {};
  options.format = 'binary';

  /**
   * @private @const {!grpc.web.GrpcWebClientBase} The client
   */
  this.client_ = new grpc.web.GrpcWebClientBase(options);

  /**
   * @private @const {string} The hostname
   */
  this.hostname_ = hostname;

};


/**
 * @const
 * @type {!grpc.web.MethodDescriptor<
 *   !proto.a6.Query,
 *   !proto.a6.Route>}
 */
const methodDescriptor_RouteService_GetRoute = new grpc.web.MethodDescriptor(
  '/a6.RouteService/GetRoute',
  grpc.web.MethodType.UNARY,
  proto.a6.Query,
  proto.a6.Route,
  /**
   * @param {!proto.a6.Query} request
   * @return {!Uint8Array}
   */
  function(request) {
    return request.serializeBinary();
  },
  proto.a6.Route.deserializeBinary
);


/**
 * @param {!proto.a6.Query} request The
 *     request proto
 * @param {?Object<string, string>} metadata User defined
 *     call metadata
 * @param {function(?grpc.web.RpcError, ?proto.a6.Route)}
 *     callback The callback function(error, response)
 * @return {!grpc.web.ClientReadableStream<!proto.a6.Route>|undefined}
 *     The XHR Node Readable Stream
 */
proto.a6.RouteServiceClient.prototype.getRoute =
    function(request, metadata, callback) {
  return this.client_.rpcCall(this.hostname_ +
      '/a6.RouteService/GetRoute',
      request,
      metadata || {},
      methodDescriptor_RouteService_GetRoute,
      callback);
};


/**
 * @param {!proto.a6.Query} request The
 *     request proto
 * @param {?Object<string, string>=} metadata User defined
 *     call metadata
 * @return {!Promise<!proto.a6.Route>}
 *     Promise that resolves to the response
 */
proto.a6.RouteServicePromiseClient.prototype.getRoute =
    function(request, metadata) {
  return this.client_.unaryCall(this.hostname_ +
      '/a6.RouteService/GetRoute',
      request,
      metadata || {},
      methodDescriptor_RouteService_GetRoute);
};


/**
 * @const
 * @type {!grpc.web.MethodDescriptor<
 *   !proto.a6.Query,
 *   !proto.a6.Route>}
 */
const methodDescriptor_RouteService_GetRoutes = new grpc.web.MethodDescriptor(
  '/a6.RouteService/GetRoutes',
  grpc.web.MethodType.SERVER_STREAMING,
  proto.a6.Query,
  proto.a6.Route,
  /**
   * @param {!proto.a6.Query} request
   * @return {!Uint8Array}
   */
  function(request) {
    return request.serializeBinary();
  },
  proto.a6.Route.deserializeBinary
);


/**
 * @param {!proto.a6.Query} request The request proto
 * @param {?Object<string, string>=} metadata User defined
 *     call metadata
 * @return {!grpc.web.ClientReadableStream<!proto.a6.Route>}
 *     The XHR Node Readable Stream
 */
proto.a6.RouteServiceClient.prototype.getRoutes =
    function(request, metadata) {
  return this.client_.serverStreaming(this.hostname_ +
      '/a6.RouteService/GetRoutes',
      request,
      metadata || {},
      methodDescriptor_RouteService_GetRoutes);
};


/**
 * @param {!proto.a6.Query} request The request proto
 * @param {?Object<string, string>=} metadata User defined
 *     call metadata
 * @return {!grpc.web.ClientReadableStream<!proto.a6.Route>}
 *     The XHR Node Readable Stream
 */
proto.a6.RouteServicePromiseClient.prototype.getRoutes =
    function(request, metadata) {
  return this.client_.serverStreaming(this.hostname_ +
      '/a6.RouteService/GetRoutes',
      request,
      metadata || {},
      methodDescriptor_RouteService_GetRoutes);
};


module.exports = proto.a6;

