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
proto.a6 = require('./routes_pb.js');

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
 *   !proto.a6.Empty,
 *   !proto.a6.Response>}
 */
const methodDescriptor_RouteService_FlushAll = new grpc.web.MethodDescriptor(
  '/a6.RouteService/FlushAll',
  grpc.web.MethodType.UNARY,
  proto.a6.Empty,
  proto.a6.Response,
  /**
   * @param {!proto.a6.Empty} request
   * @return {!Uint8Array}
   */
  function(request) {
    return request.serializeBinary();
  },
  proto.a6.Response.deserializeBinary
);


/**
 * @param {!proto.a6.Empty} request The
 *     request proto
 * @param {?Object<string, string>} metadata User defined
 *     call metadata
 * @param {function(?grpc.web.RpcError, ?proto.a6.Response)}
 *     callback The callback function(error, response)
 * @return {!grpc.web.ClientReadableStream<!proto.a6.Response>|undefined}
 *     The XHR Node Readable Stream
 */
proto.a6.RouteServiceClient.prototype.flushAll =
    function(request, metadata, callback) {
  return this.client_.rpcCall(this.hostname_ +
      '/a6.RouteService/FlushAll',
      request,
      metadata || {},
      methodDescriptor_RouteService_FlushAll,
      callback);
};


/**
 * @param {!proto.a6.Empty} request The
 *     request proto
 * @param {?Object<string, string>=} metadata User defined
 *     call metadata
 * @return {!Promise<!proto.a6.Response>}
 *     Promise that resolves to the response
 */
proto.a6.RouteServicePromiseClient.prototype.flushAll =
    function(request, metadata) {
  return this.client_.unaryCall(this.hostname_ +
      '/a6.RouteService/FlushAll',
      request,
      metadata || {},
      methodDescriptor_RouteService_FlushAll);
};


/**
 * @const
 * @type {!grpc.web.MethodDescriptor<
 *   !proto.a6.Empty,
 *   !proto.a6.Response>}
 */
const methodDescriptor_RouteService_GetAll = new grpc.web.MethodDescriptor(
  '/a6.RouteService/GetAll',
  grpc.web.MethodType.UNARY,
  proto.a6.Empty,
  proto.a6.Response,
  /**
   * @param {!proto.a6.Empty} request
   * @return {!Uint8Array}
   */
  function(request) {
    return request.serializeBinary();
  },
  proto.a6.Response.deserializeBinary
);


/**
 * @param {!proto.a6.Empty} request The
 *     request proto
 * @param {?Object<string, string>} metadata User defined
 *     call metadata
 * @param {function(?grpc.web.RpcError, ?proto.a6.Response)}
 *     callback The callback function(error, response)
 * @return {!grpc.web.ClientReadableStream<!proto.a6.Response>|undefined}
 *     The XHR Node Readable Stream
 */
proto.a6.RouteServiceClient.prototype.getAll =
    function(request, metadata, callback) {
  return this.client_.rpcCall(this.hostname_ +
      '/a6.RouteService/GetAll',
      request,
      metadata || {},
      methodDescriptor_RouteService_GetAll,
      callback);
};


/**
 * @param {!proto.a6.Empty} request The
 *     request proto
 * @param {?Object<string, string>=} metadata User defined
 *     call metadata
 * @return {!Promise<!proto.a6.Response>}
 *     Promise that resolves to the response
 */
proto.a6.RouteServicePromiseClient.prototype.getAll =
    function(request, metadata) {
  return this.client_.unaryCall(this.hostname_ +
      '/a6.RouteService/GetAll',
      request,
      metadata || {},
      methodDescriptor_RouteService_GetAll);
};


/**
 * @const
 * @type {!grpc.web.MethodDescriptor<
 *   !proto.a6.Request,
 *   !proto.a6.Response>}
 */
const methodDescriptor_RouteService_Get = new grpc.web.MethodDescriptor(
  '/a6.RouteService/Get',
  grpc.web.MethodType.UNARY,
  proto.a6.Request,
  proto.a6.Response,
  /**
   * @param {!proto.a6.Request} request
   * @return {!Uint8Array}
   */
  function(request) {
    return request.serializeBinary();
  },
  proto.a6.Response.deserializeBinary
);


/**
 * @param {!proto.a6.Request} request The
 *     request proto
 * @param {?Object<string, string>} metadata User defined
 *     call metadata
 * @param {function(?grpc.web.RpcError, ?proto.a6.Response)}
 *     callback The callback function(error, response)
 * @return {!grpc.web.ClientReadableStream<!proto.a6.Response>|undefined}
 *     The XHR Node Readable Stream
 */
proto.a6.RouteServiceClient.prototype.get =
    function(request, metadata, callback) {
  return this.client_.rpcCall(this.hostname_ +
      '/a6.RouteService/Get',
      request,
      metadata || {},
      methodDescriptor_RouteService_Get,
      callback);
};


/**
 * @param {!proto.a6.Request} request The
 *     request proto
 * @param {?Object<string, string>=} metadata User defined
 *     call metadata
 * @return {!Promise<!proto.a6.Response>}
 *     Promise that resolves to the response
 */
proto.a6.RouteServicePromiseClient.prototype.get =
    function(request, metadata) {
  return this.client_.unaryCall(this.hostname_ +
      '/a6.RouteService/Get',
      request,
      metadata || {},
      methodDescriptor_RouteService_Get);
};


/**
 * @const
 * @type {!grpc.web.MethodDescriptor<
 *   !proto.a6.Request,
 *   !proto.a6.Response>}
 */
const methodDescriptor_RouteService_Insert = new grpc.web.MethodDescriptor(
  '/a6.RouteService/Insert',
  grpc.web.MethodType.UNARY,
  proto.a6.Request,
  proto.a6.Response,
  /**
   * @param {!proto.a6.Request} request
   * @return {!Uint8Array}
   */
  function(request) {
    return request.serializeBinary();
  },
  proto.a6.Response.deserializeBinary
);


/**
 * @param {!proto.a6.Request} request The
 *     request proto
 * @param {?Object<string, string>} metadata User defined
 *     call metadata
 * @param {function(?grpc.web.RpcError, ?proto.a6.Response)}
 *     callback The callback function(error, response)
 * @return {!grpc.web.ClientReadableStream<!proto.a6.Response>|undefined}
 *     The XHR Node Readable Stream
 */
proto.a6.RouteServiceClient.prototype.insert =
    function(request, metadata, callback) {
  return this.client_.rpcCall(this.hostname_ +
      '/a6.RouteService/Insert',
      request,
      metadata || {},
      methodDescriptor_RouteService_Insert,
      callback);
};


/**
 * @param {!proto.a6.Request} request The
 *     request proto
 * @param {?Object<string, string>=} metadata User defined
 *     call metadata
 * @return {!Promise<!proto.a6.Response>}
 *     Promise that resolves to the response
 */
proto.a6.RouteServicePromiseClient.prototype.insert =
    function(request, metadata) {
  return this.client_.unaryCall(this.hostname_ +
      '/a6.RouteService/Insert',
      request,
      metadata || {},
      methodDescriptor_RouteService_Insert);
};


/**
 * @const
 * @type {!grpc.web.MethodDescriptor<
 *   !proto.a6.Request,
 *   !proto.a6.Response>}
 */
const methodDescriptor_RouteService_Update = new grpc.web.MethodDescriptor(
  '/a6.RouteService/Update',
  grpc.web.MethodType.UNARY,
  proto.a6.Request,
  proto.a6.Response,
  /**
   * @param {!proto.a6.Request} request
   * @return {!Uint8Array}
   */
  function(request) {
    return request.serializeBinary();
  },
  proto.a6.Response.deserializeBinary
);


/**
 * @param {!proto.a6.Request} request The
 *     request proto
 * @param {?Object<string, string>} metadata User defined
 *     call metadata
 * @param {function(?grpc.web.RpcError, ?proto.a6.Response)}
 *     callback The callback function(error, response)
 * @return {!grpc.web.ClientReadableStream<!proto.a6.Response>|undefined}
 *     The XHR Node Readable Stream
 */
proto.a6.RouteServiceClient.prototype.update =
    function(request, metadata, callback) {
  return this.client_.rpcCall(this.hostname_ +
      '/a6.RouteService/Update',
      request,
      metadata || {},
      methodDescriptor_RouteService_Update,
      callback);
};


/**
 * @param {!proto.a6.Request} request The
 *     request proto
 * @param {?Object<string, string>=} metadata User defined
 *     call metadata
 * @return {!Promise<!proto.a6.Response>}
 *     Promise that resolves to the response
 */
proto.a6.RouteServicePromiseClient.prototype.update =
    function(request, metadata) {
  return this.client_.unaryCall(this.hostname_ +
      '/a6.RouteService/Update',
      request,
      metadata || {},
      methodDescriptor_RouteService_Update);
};


/**
 * @const
 * @type {!grpc.web.MethodDescriptor<
 *   !proto.a6.Request,
 *   !proto.a6.Response>}
 */
const methodDescriptor_RouteService_Remove = new grpc.web.MethodDescriptor(
  '/a6.RouteService/Remove',
  grpc.web.MethodType.UNARY,
  proto.a6.Request,
  proto.a6.Response,
  /**
   * @param {!proto.a6.Request} request
   * @return {!Uint8Array}
   */
  function(request) {
    return request.serializeBinary();
  },
  proto.a6.Response.deserializeBinary
);


/**
 * @param {!proto.a6.Request} request The
 *     request proto
 * @param {?Object<string, string>} metadata User defined
 *     call metadata
 * @param {function(?grpc.web.RpcError, ?proto.a6.Response)}
 *     callback The callback function(error, response)
 * @return {!grpc.web.ClientReadableStream<!proto.a6.Response>|undefined}
 *     The XHR Node Readable Stream
 */
proto.a6.RouteServiceClient.prototype.remove =
    function(request, metadata, callback) {
  return this.client_.rpcCall(this.hostname_ +
      '/a6.RouteService/Remove',
      request,
      metadata || {},
      methodDescriptor_RouteService_Remove,
      callback);
};


/**
 * @param {!proto.a6.Request} request The
 *     request proto
 * @param {?Object<string, string>=} metadata User defined
 *     call metadata
 * @return {!Promise<!proto.a6.Response>}
 *     Promise that resolves to the response
 */
proto.a6.RouteServicePromiseClient.prototype.remove =
    function(request, metadata) {
  return this.client_.unaryCall(this.hostname_ +
      '/a6.RouteService/Remove',
      request,
      metadata || {},
      methodDescriptor_RouteService_Remove);
};


module.exports = proto.a6;

