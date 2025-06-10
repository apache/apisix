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
import axios, {
  type AxiosRequestConfig,
  type Method,
  type RawAxiosRequestHeaders,
} from 'axios';

export const request = async (
  url: string,
  method: Method = 'GET',
  body?: object,
  headers?: RawAxiosRequestHeaders,
  config?: AxiosRequestConfig,
) => {
  return axios.request({
    method,
    // TODO: use 9180 for admin api
    baseURL: 'http://127.0.0.1:1984',
    url,
    data: body,
    headers: {
      'X-API-KEY': 'edd1c9f034335f136f87ad84b625c8f1',
      ...headers,
    },
    ...config,
  });
};
