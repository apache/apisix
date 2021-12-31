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
const {RouteServiceClient} = require('./a6/routes_grpc_web_pb')

const FUNCTION_ALL = "ALL"
const FUNCTION_GET = "GET"
const FUNCTION_POST = "POST"
const FUNCTION_PUT = "PUT"
const FUNCTION_DEL = "DEL"
const FUNCTION_FLUSH = "FLUSH"

const functions = [FUNCTION_ALL, FUNCTION_GET, FUNCTION_POST, FUNCTION_PUT, FUNCTION_DEL, FUNCTION_FLUSH]

class gRPCWebClient {
    constructor() {
        this.client = new RouteServiceClient("http://127.0.0.1:1984/grpc", null, null)
    };

    flush() {
        let request = new Empty()
        this.client.flushAll(request, {}, function (error, response) {
            if (error) {
                console.log(error)
                return
            }
            console.log(JSON.stringify(response.toObject().routesMap))
        });
    }

    all() {
        let request = new Empty()
        this.client.getAll(request, {}, function (error, response) {
            if (error) {
                console.log(error)
                return
            }
            console.log(JSON.stringify(response.toObject().routesMap))
        });
    }

    get(params) {
        if (params[0] === null) {
            console.log("route ID invalid")
            return
        }
        let request = new Request()
        request.setId(params[0])
        this.client.get(request, {}, function (error, response) {
            if (error) {
                console.log(error)
                return
            }
            console.log(JSON.stringify(response.toObject().route))
        });
    }

    post(params) {
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
        this.client.insert(request, {}, function (error, response) {
            if (error) {
                console.log(error)
                return
            }
            console.log(JSON.stringify(response.toObject().routesMap))
        });
    }

    put(params) {
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
        this.client.update(request, {}, function (error, response) {
            if (error) {
                console.log(error)
                return
            }
            console.log(JSON.stringify(response.toObject().routesMap))
        })
    }

    del() {
        if (params[0] === null) {
            console.log("route ID invalid")
            return
        }
        let request = new Request()
        request.setId(params[0])
        this.client.remove(request, {}, function (error, response) {
            if (error) {
                console.log(error)
                return
            }
            console.log(JSON.stringify(response.toObject().routesMap))
        })
    }
}


const arguments = process.argv.splice(2)

if (arguments.length === 0) {
    console.log("please input dispatch function, e.g: node client.js insert arg_id arg_name arg_path")
    return
}

const func = arguments[0].toUpperCase()
if (!functions.includes(func)) {
    console.log("dispatch function not found")
    return
}

const params = arguments.splice(1)

let grpc = new gRPCWebClient();

if (func === FUNCTION_GET) {
    grpc.get(params)
} else if (func === FUNCTION_POST) {
    grpc.post(params)
} else if (func === FUNCTION_PUT) {
    grpc.put(params)
} else if (func === FUNCTION_DEL) {
    grpc.del(params)
} else if (func === FUNCTION_FLUSH) {
    grpc.flush()
} else {
    grpc.all()
}
