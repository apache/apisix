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

const RouteServiceQuery = require('./a6/route_pb').Query
const RouteServiceBinProtocolClient = require('./a6/route_grpc_web_bin_pb').RouteServiceClient
const RouteServiceTextProtocolClient = require('./a6/route_grpc_web_text_pb').RouteServiceClient

const MODE_TEXT = "TEXT"
const MODE_BIN = "BIN"

const modes = [MODE_TEXT, MODE_BIN];


const TYPE_UNARY = "UNARY"
const TYPE_STREAM = "STREAM"

const types = [TYPE_UNARY, TYPE_STREAM];


class gRPCWebClient {
    constructor() {
        this.clients = {}
        this.clients[MODE_BIN] = new RouteServiceBinProtocolClient("http://127.0.0.1:1984/grpc/web");
        this.clients[MODE_TEXT] = new RouteServiceTextProtocolClient("http://127.0.0.1:1984/grpc/web");
    };

    unary(mode) {
        let query = new RouteServiceQuery()
        query.setName("hello")
        this.clients[mode].getRoute(query, {}, function (error, response) {
            if (error) {
                console.log(error);
                return
            }
            console.log(JSON.stringify(response.toObject()));
        }).on("status", function (status) {
            console.log("Status:", status);
        });
    }

    stream(mode) {
        let query = new RouteServiceQuery()
        var stream = this.clients[mode].getRoutes(query, {});
        stream.on('data', function(response) {
          console.log(JSON.stringify(response.toObject()));
        });

        stream.on('end', function(end) {
            stream.cancel();
        });

        stream.on("status", function (status) {
            console.log("Status:", status);
        });
    }
}


const arguments = process.argv.splice(2)

if (arguments.length !== 2) {
    console.log("please input dispatch function, e.g: node client.js [mode] [type]")
    return
}

const mode = arguments[0].toUpperCase()
if (!modes.includes(mode)) {
    console.log("dispatch mode not found")
    return
}

const t = arguments[1].toUpperCase()
if (!types.includes(t)) {
    console.log("dispatch types not found")
    return
}

let grpc = new gRPCWebClient();

if (t === TYPE_UNARY) {
    grpc.unary(mode)
} else {
    grpc.stream(mode)
}
