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
-- A Swagger 2.0 document. The plugin schema does not restrict the document
-- version, and 2.0 differs structurally: bodies live in `parameters` with
-- `in: body` / `in: formData` rather than in `requestBody`, schemas live under
-- `definitions`, and the server comes from host/basePath/schemes. Whatever the
-- two implementations do with it, they have to do the same thing.
return {
    swagger = "2.0",
    info = { title = "Swagger 2.0", version = "1.0.0" },
    host = "127.0.0.1:11460",
    basePath = "/v2",
    schemes = { "http" },
    consumes = { "application/json" },
    produces = { "application/json" },
    definitions = {
        Pet = {
            type = "object",
            required = { "name" },
            properties = {
                id = { type = "integer", format = "int64" },
                name = { type = "string" },
                status = { type = "string", enum = { "available", "sold" } },
            },
        },
    },
    paths = {
        ["/s2/pet"] = { post = {
            operationId = "addPetV2",
            summary = "body parameter, the 2.0 way",
            parameters = {
                { name = "body", ["in"] = "body", required = true,
                  schema = { ["$ref"] = "#/definitions/Pet" } },
            },
        } },
        ["/s2/pet/{petId}"] = { get = {
            operationId = "getPetV2",
            parameters = {
                { name = "petId", ["in"] = "path", required = true,
                  type = "integer", format = "int64" },
                { name = "verbose", ["in"] = "query", type = "boolean",
                  default = true },
                { name = "X-Trace", ["in"] = "header", type = "string" },
            },
        } },
        ["/s2/pet/form"] = { post = {
            operationId = "formPetV2",
            consumes = { "application/x-www-form-urlencoded" },
            parameters = {
                { name = "name", ["in"] = "formData", required = true,
                  type = "string" },
                { name = "status", ["in"] = "formData", type = "string" },
            },
        } },
        ["/s2/pet/noid"] = { get = {} },
    },
}
