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

global.XMLHttpRequest = require('xhr2')

const {Empty, Request, Route} = require('./a6/routes_pb')
const RouteServiceBinProtocolClient = require('./a6/routes_grpc_web_bin_pb').RouteServiceClient
const RouteServiceTextProtocolClient = require('./a6/routes_grpc_web_text_pb').RouteServiceClient

const MODE_TEXT = "TEXT"
const MODE_BIN  = "BIN"

const modes = [MODE_TEXT, MODE_BIN];

const FUNCTION_ALL = "ALL"
const FUNCTION_GET = "GET"
const FUNCTION_POST = "POST"
const FUNCTION_PUT = "PUT"
const FUNCTION_DEL = "DEL"
const FUNCTION_FLUSH = "FLUSH"

const functions = [FUNCTION_ALL, FUNCTION_GET, FUNCTION_POST, FUNCTION_PUT, FUNCTION_DEL, FUNCTION_FLUSH]

class gRPCWebClient {
    constructor() {
        this.clients = {}
        this.clients[MODE_BIN] = new RouteServiceBinProtocolClient("http://127.0.0.1:1984/grpc")
        this.clients[MODE_TEXT] = new RouteServiceTextProtocolClient("http://127.0.0.1:1984/grpc")
    };

    flush(mode) {
        let request = new Empty()
        this.clients[mode].flushAll(request, {}, function (error, response) {
            if (error) {
                console.log(error)
                return
            }
            console.log(JSON.stringify(response.toObject().routesMap))
        });
    }

    all(mode) {
        let request = new Empty()
        this.clients[mode].getAll(request, {}, function (error, response) {
            if (error) {
                console.log(error)
                return
            }
            console.log(JSON.stringify(response.toObject().routesMap))
        });
    }

    get(mode, params) {
        if (params[0] === null) {
            console.log("route ID invalid")
            return
        }
        let request = new Request()
        request.setId(params[0])
        this.clients[mode].get(request, {}, function (error, response) {
            if (error) {
                console.log(error)
                return
            }
            console.log(JSON.stringify(response.toObject().route))
        });
    }

    post(mode, params) {
        if (params[0] === null) {
            console.log("route ID invalid")
            return
        }
        if (params[1] === null) {
            console.log("route Name invalid")
            return
        }
        if (params[2] === null) {
            console.log("route Path invalid")
            return
        }
        let request = new Request()
        let route = new Route()
        request.setId(params[0])
        route.setName(params[1])
        route.setPath(params[2])
        request.setRoute(route)
        this.clients[mode].insert(request, {}, function (error, response) {
            if (error) {
                console.log(error)
                return
            }
            console.log(JSON.stringify(response.toObject().routesMap))
        });
    }

    put(mode, params) {
        if (params[0] === null) {
            console.log("route ID invalid")
            return
        }
        if (params[1] === null) {
            console.log("route Name invalid")
            return
        }
        if (params[2] === null) {
            console.log("route Path invalid")
            return
        }
        let request = new Request()
        let route = new Route()
        request.setId(params[0])
        route.setName(params[1])
        route.setPath(params[2])
        request.setRoute(route)
        this.clients[mode].update(request, {}, function (error, response) {
            if (error) {
                console.log(error)
                return
            }
            console.log(JSON.stringify(response.toObject().routesMap))
        })
    }

    del(mode) {
        if (params[0] === null) {
            console.log("route ID invalid")
            return
        }
        let request = new Request()
        request.setId(params[0])
        this.clients[mode].remove(request, {}, function (error, response) {
            if (error) {
                console.log(error)
                return
            }
            console.log(JSON.stringify(response.toObject().routesMap))
        })
    }
}


const arguments = process.argv.splice(2)

if (arguments.length < 2) {
    console.log("please input dispatch function, e.g: node client.js [mode] [action] [params...]")
    return
}

const mode = arguments[0].toUpperCase()
if (!modes.includes(mode)) {
    console.log("dispatch mode not found")
    return
}

const func = arguments[1].toUpperCase()
if (!functions.includes(func)) {
    console.log("dispatch function not found")
    return
}

const params = arguments.splice(2)

let grpc = new gRPCWebClient();

if (func === FUNCTION_GET) {
    grpc.get(mode, params)
} else if (func === FUNCTION_POST) {
    grpc.post(mode, params)
} else if (func === FUNCTION_PUT) {
    grpc.put(mode, params)
} else if (func === FUNCTION_DEL) {
    grpc.del(mode, params)
} else if (func === FUNCTION_FLUSH) {
    grpc.flush(mode)
} else {
    grpc.all(mode)
}
