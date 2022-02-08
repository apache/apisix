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
	"math/rand"

	"github.com/tetratelabs/proxy-wasm-go-sdk/proxywasm"
	"github.com/tetratelabs/proxy-wasm-go-sdk/proxywasm/types"

	// tinygo doesn't support encoding/json, see https://github.com/tinygo-org/tinygo/issues/447
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

type pluginContext struct {
	types.DefaultPluginContext
	Body       []byte
	HttpStatus uint32
	Percentage int
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
	ctx.Body = v.GetStringBytes("body")
	ctx.HttpStatus = uint32(v.GetUint("http_status"))
	if v.Exists("percentage") {
		ctx.Percentage = v.GetInt("percentage")
	} else {
		ctx.Percentage = 100
	}

	// schema check
	if ctx.HttpStatus < 200 {
		proxywasm.LogError("bad http_status")
		return types.OnPluginStartStatusFailed
	}
	if ctx.Percentage < 0 || ctx.Percentage > 100 {
		proxywasm.LogError("bad percentage")
		return types.OnPluginStartStatusFailed
	}

	return types.OnPluginStartStatusOK
}

func (ctx *pluginContext) NewHttpContext(contextID uint32) types.HttpContext {
	return &httpLifecycle{parent: ctx}
}

type httpLifecycle struct {
	types.DefaultHttpContext
	parent *pluginContext
}

func sampleHit(percentage int) bool {
	return rand.Intn(100) < percentage
}

func (ctx *httpLifecycle) OnHttpRequestHeaders(numHeaders int, endOfStream bool) types.Action {
	plugin := ctx.parent
	if !sampleHit(plugin.Percentage) {
		return types.ActionContinue
	}

	err := proxywasm.SendHttpResponse(plugin.HttpStatus, nil, plugin.Body, -1)
	if err != nil {
		proxywasm.LogErrorf("failed to send local response: %v", err)
		return types.ActionContinue
	}
	return types.ActionPause
}
