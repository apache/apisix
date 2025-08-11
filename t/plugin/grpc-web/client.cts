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
//@ts-expect-error no typing for xhr2
import XMLHttpRequest from 'xhr2';

import { RouteServiceClient } from './a6/RouteServiceClientPb';
import message from './a6/route_pb';

// inject xhr polyfill for grpc-web
(global as any).XMLHttpRequest = XMLHttpRequest;

const RPC_CALL_FORMAT = {
  TEXT: 'TEXT',
  BIN: 'BIN',
} as const;
type RPC_CALL_FORMAT = keyof typeof RPC_CALL_FORMAT;
const formats = [RPC_CALL_FORMAT.TEXT, RPC_CALL_FORMAT.BIN];

const RPC_CALL_TYPE = {
  UNARY: 'UNARY',
  STREAM: 'STREAM',
  EXPECT_ERROR: 'EXPECT_ERROR',
} as const;
type RPC_CALL_TYPE = keyof typeof RPC_CALL_TYPE;
const types = [
  RPC_CALL_TYPE.UNARY,
  RPC_CALL_TYPE.STREAM,
  RPC_CALL_TYPE.EXPECT_ERROR,
];

class gRPCWebClient {
  private clients = {
    [RPC_CALL_FORMAT.BIN]: new RouteServiceClient(
      'http://127.0.0.1:1984/grpc/web',
      null,
      { format: 'binary' },
    ),
    [RPC_CALL_FORMAT.TEXT]: new RouteServiceClient(
      'http://127.0.0.1:1984/grpc/web',
      null,
      { format: 'text' },
    ),
  };

  [RPC_CALL_TYPE.UNARY](format: RPC_CALL_FORMAT) {
    let query = new message.Query().setName('hello');
    this.clients[format]
      .getRoute(query, {}, (error, response) => {
        if (error) {
          console.log(error);
          return;
        }
        console.log(JSON.stringify(response.toObject()));
      })
      .on('status', (status) => console.log('Status:', status));
  }

  [RPC_CALL_TYPE.STREAM](format: RPC_CALL_FORMAT) {
    let query = new message.Query();
    let stream = this.clients[format].getRoutes(query, {});

    stream.on('data', (response) =>
      console.log(JSON.stringify(response.toObject())),
    );

    stream.on('end', () => stream.cancel());

    stream.on('status', (status) => console.log('Status:', status));
  }

  [RPC_CALL_TYPE.EXPECT_ERROR](format: RPC_CALL_FORMAT) {
    this.clients[format]
      .getError(new message.Query(), null, () => {})
      .on('status', (status) => {
        console.log(`Status: ${status.code}, Details: ${status.details}`);
      });
  }
}

(async () => {
  const args = process.argv.splice(2);

  if (args.length !== 2) {
    console.log(
      'please input dispatch function, e.g: node client.js [format] [type]',
    );
    return;
  }

  const format = args[0].toUpperCase() as RPC_CALL_FORMAT;
  if (!formats.includes(format)) {
    console.log('dispatch format not found');
    return;
  }

  const type = args[1].toUpperCase() as RPC_CALL_TYPE;
  if (!types.includes(type)) {
    console.log('dispatch type not found');
    return;
  }

  let grpc = new gRPCWebClient();

  grpc[type](format);
})();
