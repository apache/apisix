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

package main

import (
	"github.com/tetratelabs/proxy-wasm-go-sdk/proxywasm"
	"github.com/tetratelabs/proxy-wasm-go-sdk/proxywasm/types"

	"github.com/valyala/fastjson"
)

func main() {
	proxywasm.SetVMContext(&vmContext{})
}

type vmContext struct {
	types.DefaultVMContext
}

func (*vmContext) NewPluginContext(contextID uint32) types.PluginContext {
	return &pluginContext{}
}

type header struct {
	Name  string
	Value string
}

type pluginContext struct {
	types.DefaultPluginContext
	Headers []header
	Body    []byte
}

func (ctx *pluginContext) OnPluginStart(pluginConfigurationSize int) types.OnPluginStartStatus {
	data, err := proxywasm.GetPluginConfiguration()
	if err != nil {
		proxywasm.LogErrorf("error reading plugin configuration: %v", err)
		return types.OnPluginStartStatusFailed
	}

	var p fastjson.Parser
	v, err := p.ParseBytes(data)
	if err != nil {
		proxywasm.LogErrorf("error decoding plugin configuration: %v", err)
		return types.OnPluginStartStatusFailed
	}
	headers := v.GetArray("headers")
	ctx.Headers = make([]header, len(headers))
	for i, hdr := range headers {
		ctx.Headers[i] = header{
			Name:  string(hdr.GetStringBytes("name")),
			Value: string(hdr.GetStringBytes("value")),
		}
	}

	body := v.GetStringBytes("body")
	ctx.Body = body

	return types.OnPluginStartStatusOK
}

func (ctx *pluginContext) NewHttpContext(contextID uint32) types.HttpContext {
	return &httpContext{parent: ctx}
}

type httpContext struct {
	types.DefaultHttpContext
	parent *pluginContext
}

func (ctx *httpContext) OnHttpResponseHeaders(numHeaders int, endOfStream bool) types.Action {
	plugin := ctx.parent
	for _, hdr := range plugin.Headers {
		proxywasm.ReplaceHttpResponseHeader(hdr.Name, hdr.Value)
	}

	if len(plugin.Body) > 0 {
		proxywasm.SetProperty([]string{"wasm_process_resp_body"}, []byte("true"))
	}

	return types.ActionContinue
}

func (ctx *httpContext) OnHttpResponseBody(bodySize int, endOfStream bool) types.Action {
	plugin := ctx.parent

	if len(plugin.Body) > 0 && !endOfStream {
		// TODO support changing body
		body, err := proxywasm.GetHttpResponseBody(0, bodySize)
		if err != nil {
			proxywasm.LogErrorf("failed to get body: %v", err)
			return types.ActionContinue
		}
		proxywasm.LogWarnf("get body [%s]", string(body))
	}

	return types.ActionContinue
}
