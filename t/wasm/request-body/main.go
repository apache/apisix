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
	return &pluginContext{contextID: contextID}
}

type pluginContext struct {
	types.DefaultPluginContext
	contextID      uint32
	start          int
	size           int
	processReqBody bool
}

func (ctx *pluginContext) OnPluginStart(pluginConfigurationSize int) types.OnPluginStartStatus {
	data, err := proxywasm.GetPluginConfiguration()
	if err != nil {
		proxywasm.LogCriticalf("error reading plugin configuration: %v", err)
		return types.OnPluginStartStatusFailed
	}

	var conf *fastjson.Value
	var p fastjson.Parser
	conf, err = p.ParseBytes(data)
	if err != nil {
		proxywasm.LogErrorf("error decoding plugin configuration: %v", err)
		return types.OnPluginStartStatusFailed
	}

	ctx.start = conf.GetInt("start")
	ctx.size = conf.GetInt("size")
	ctx.processReqBody = conf.GetBool("processReqBody")
	return types.OnPluginStartStatusOK
}

func (ctx *pluginContext) NewHttpContext(contextID uint32) types.HttpContext {
	return &httpContext{pluginCtx: ctx, contextID: contextID}
}

type httpContext struct {
	types.DefaultHttpContext
	pluginCtx *pluginContext
	contextID uint32
}

func (ctx *httpContext) OnHttpRequestHeaders(numHeaders int, endOfStream bool) types.Action {
	if ctx.pluginCtx.processReqBody {
		proxywasm.SetProperty([]string{"wasm_process_req_body"}, []byte("true"))
	}

	return types.ActionContinue
}

func (ctx *httpContext) OnHttpRequestBody(bodySize int, endOfStream bool) types.Action {
	size := ctx.pluginCtx.size
	if size == 0 {
		size = bodySize
	}

	body, err := proxywasm.GetHttpRequestBody(ctx.pluginCtx.start, size)
	if err != nil {
		proxywasm.LogErrorf("failed to get body: %v", err)
		return types.ActionContinue
	}

	proxywasm.LogWarnf("request get body: %v", string(body))
	return types.ActionContinue
}
