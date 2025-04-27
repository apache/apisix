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

import axios from "axios";
import YAML from "yaml";

const config1 = {
  routes: [
    {
      id: "r1",
      uri: "/r1",
      upstream: {
        nodes: { "127.0.0.1:1980": 1 },
        type: "roundrobin",
      },
      plugins: { "proxy-rewrite": { uri: "/hello" } },
    },
  ],
};
const config2 = {
  routes: [
    {
      id: "r2",
      uri: "/r2",
      upstream: {
        nodes: { "127.0.0.1:1980": 1 },
        type: "roundrobin",
      },
      plugins: { "proxy-rewrite": { uri: "/hello" } },
    },
  ],
};
const clientConfig = {
  baseURL: "http://localhost:1984",
  headers: {
    "X-API-KEY": "edd1c9f034335f136f87ad84b625c8f1",
  },
};

describe("Admin - Standalone", () => {
  const client = axios.create(clientConfig);
  client.interceptors.response.use((response) => {
    const contentType = response.headers["content-type"] || "";
    if (
      contentType.includes("application/yaml") &&
      typeof response.data === "string" &&
      response.config.responseType !== "text"
    )
      response.data = YAML.parse(response.data);
    return response;
  });

  describe("Normal", () => {
    it("dump empty config (default json format)", async () => {
      const resp = await client.get("/apisix/admin/configs");
      expect(resp.status).toEqual(200);
      expect(resp.headers["content-type"]).toEqual("application/json");
      expect(resp.headers["x-apisix-conf-version"]).toEqual("0");
      expect(resp.data).toEqual({});
    });

    it("dump empty config (yaml format)", async () => {
      const resp = await client.get("/apisix/admin/configs", {
        headers: { Accept: "application/yaml" },
      });
      expect(resp.status).toEqual(200);
      expect(resp.headers["content-type"]).toEqual("application/yaml");
      expect(resp.headers["x-apisix-conf-version"]).toEqual("0");

      // The lyaml-encoded empty Lua table becomes an array, which is expected, but shouldn't be
      expect(resp.data).toEqual([]);
    });

    it("update config (add routes, by json)", async () => {
      const resp = await client.put("/apisix/admin/configs", config1, {
        params: { conf_version: 1 },
      });
      expect(resp.status).toEqual(202);
    });

    it("dump config (json format)", async () => {
      const resp = await client.get("/apisix/admin/configs");
      expect(resp.status).toEqual(200);
      expect(resp.headers["x-apisix-conf-version"]).toEqual("1");
    });

    it("dump config (yaml format)", async () => {
      const resp = await client.get("/apisix/admin/configs", {
        headers: { Accept: "application/yaml" },
        responseType: 'text',
      });
      expect(resp.status).toEqual(200);
      expect(resp.headers["x-apisix-conf-version"]).toEqual("1");
      expect(resp.data).toContain("routes:")
      expect(resp.data).toContain("id: r1")
      expect(resp.data.startsWith('---')).toBe(false);
      expect(resp.data.endsWith('...')).toBe(false);
    });

    it('check route "r1"', async () => {
      const resp = await client.get("/r1");
      expect(resp.status).toEqual(200);
      expect(resp.data).toEqual("hello world\n");
    });

    it("update config (add routes, by yaml)", async () => {
      const resp = await client.put(
        "/apisix/admin/configs",
        YAML.stringify(config2),
        {
          params: { conf_version: 2 },
          headers: { "Content-Type": "application/yaml" },
        }
      );
      expect(resp.status).toEqual(202);
    });

    it("dump config (json format)", async () => {
      const resp = await client.get("/apisix/admin/configs");
      expect(resp.status).toEqual(200);
      expect(resp.headers["x-apisix-conf-version"]).toEqual("2");
    });

    it('check route "r1"', () =>
      expect(client.get("/r1")).rejects.toThrow(
        "Request failed with status code 404"
      ));

    it('check route "r2"', async () => {
      const resp = await client.get("/r2");
      expect(resp.status).toEqual(200);
      expect(resp.data).toEqual("hello world\n");
    });

    it("update config (delete routes)", async () => {
      const resp = await client.put(
        "/apisix/admin/configs",
        {},
        { params: { conf_version: 3 } }
      );
      expect(resp.status).toEqual(202);
    });

    it('check route "r2"', () =>
      expect(client.get("/r2")).rejects.toThrow(
        "Request failed with status code 404"
      ));
  });

  describe("Exceptions", () => {
    const clientException = axios.create({
      ...clientConfig,
      validateStatus: () => true,
    });

    it("update config (lower conf_version)", async () => {
      const resp = await clientException.put(
        "/apisix/admin/configs",
        YAML.stringify(config2),
        {
          params: { conf_version: 0 },
          headers: { "Content-Type": "application/yaml" },
        }
      );
      expect(resp.status).toEqual(400);
      expect(resp.data).toEqual({
        error_msg:
          "invalid conf_version: conf_version (0) should be greater than the current version (3)",
      });
    });

    it("update config (invalid conf_version)", async () => {
      const resp = await clientException.put(
        "/apisix/admin/configs",
        YAML.stringify(config2),
        {
          params: { conf_version: "abc" },
          headers: { "Content-Type": "application/yaml" },
        }
      );
      expect(resp.status).toEqual(400);
      expect(resp.data).toEqual({
        error_msg: "invalid conf_version: abc, should be a integer",
      });
    });

    it("update config (invalid json format)", async () => {
      const resp = await clientException.put("/apisix/admin/configs", "{abcd", {
        params: { conf_version: 4 },
      });
      expect(resp.status).toEqual(400);
      expect(resp.data).toEqual({
        error_msg:
          "invalid request body: Expected object key string but found invalid token at character 2",
        req_body: "{abcd",
      });
    });

    it("update config (not compliant with jsonschema)", async () => {
      const data = structuredClone(config1);
      (data.routes[0].uri as unknown) = 123;
      const resp = await clientException.put("/apisix/admin/configs", data);
      expect(resp.status).toEqual(400);
      expect(resp.data).toMatchObject({
        error_msg:
          'invalid routes at index 0, err: property "uri" validation failed: wrong type: expected string, got number',
      });
    });

    it("update config (empty request body)", async () => {
      const resp = await clientException.put("/apisix/admin/configs", "");
      expect(resp.status).toEqual(400);
      expect(resp.data).toEqual({
        error_msg: "invalid request body: empty request body",
      });
    });
  });
});
