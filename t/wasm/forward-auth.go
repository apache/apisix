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
	"net/url"
	"strconv"
	"strings"

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
	return &pluginContext{
		contextID:       contextID,
		upstreamHeaders: map[string]struct{}{},
		clientHeaders:   map[string]struct{}{},
		requestHeaders:  map[string]struct{}{},
	}
}

type pluginContext struct {
	types.DefaultPluginContext
	contextID uint32

	host            string
	path            string
	scheme          string
	upstreamHeaders map[string]struct{}
	clientHeaders   map[string]struct{}
	requestHeaders  map[string]struct{}
	timeout         uint32
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

	ctx.timeout = uint32(v.GetUint("timeout"))
	if ctx.timeout == 0 {
		ctx.timeout = 3000
	}

	// schema check
	if ctx.timeout < 1 || ctx.timeout > 60000 {
		proxywasm.LogError("bad timeout")
		return types.OnPluginStartStatusFailed
	}

	s := string(v.GetStringBytes("uri"))
	if s == "" {
		proxywasm.LogError("bad uri")
		return types.OnPluginStartStatusFailed
	}

	uri, err := url.Parse(s)
	if err != nil {
		proxywasm.LogErrorf("bad uri: %v", err)
		return types.OnPluginStartStatusFailed
	}

	ctx.host = uri.Host
	ctx.path = uri.Path
	ctx.scheme = uri.Scheme

	arr := v.GetArray("upstream_headers")
	for _, a := range arr {
		ctx.upstreamHeaders[strings.ToLower(string(a.GetStringBytes()))] = struct{}{}
	}

	arr = v.GetArray("request_headers")
	for _, a := range arr {
		ctx.requestHeaders[string(a.GetStringBytes())] = struct{}{}
	}

	arr = v.GetArray("client_headers")
	for _, a := range arr {
		ctx.clientHeaders[strings.ToLower(string(a.GetStringBytes()))] = struct{}{}
	}

	return types.OnPluginStartStatusOK
}

func (pluginCtx *pluginContext) NewHttpContext(contextID uint32) types.HttpContext {
	ctx := &httpContext{contextID: contextID, pluginCtx: pluginCtx}
	return ctx
}

type httpContext struct {
	types.DefaultHttpContext
	contextID uint32
	pluginCtx *pluginContext
}

func (ctx *httpContext) dispatchHttpCall(elem *fastjson.Value) {
	method, _ := proxywasm.GetHttpRequestHeader(":method")
	uri, _ := proxywasm.GetHttpRequestHeader(":path")
	scheme, _ := proxywasm.GetHttpRequestHeader(":scheme")
	host, _ := proxywasm.GetHttpRequestHeader("host")
	addr, _ := proxywasm.GetProperty([]string{"remote_addr"})

	pctx := ctx.pluginCtx
	hs := [][2]string{}
	hs = append(hs, [2]string{":scheme", pctx.scheme})
	hs = append(hs, [2]string{"host", pctx.host})
	hs = append(hs, [2]string{":path", pctx.path})
	hs = append(hs, [2]string{"X-Forwarded-Proto", scheme})
	hs = append(hs, [2]string{"X-Forwarded-Method", method})
	hs = append(hs, [2]string{"X-Forwarded-Host", host})
	hs = append(hs, [2]string{"X-Forwarded-Uri", uri})
	hs = append(hs, [2]string{"X-Forwarded-For", string(addr)})

	for k := range pctx.requestHeaders {
		h, err := proxywasm.GetHttpRequestHeader(k)

		if err != nil && err != types.ErrorStatusNotFound {
			proxywasm.LogErrorf("httpcall failed: %v", err)
			return
		}
		hs = append(hs, [2]string{k, h})
	}

	calloutID, err := proxywasm.DispatchHttpCall(pctx.host, hs, nil, nil,
		pctx.timeout, ctx.httpCallback)
	if err != nil {
		proxywasm.LogErrorf("httpcall failed: %v", err)
		return
	}
	proxywasm.LogInfof("httpcall calloutID %d, pluginCtxID %d", calloutID, ctx.pluginCtx.contextID)
}

func (ctx *httpContext) OnHttpRequestHeaders(numHeaders int, endOfStream bool) types.Action {
	data, err := proxywasm.GetPluginConfiguration()
	if err != nil {
		proxywasm.LogErrorf("error reading plugin configuration: %v", err)
		return types.ActionContinue
	}

	var p fastjson.Parser
	v, err := p.ParseBytes(data)
	if err != nil {
		proxywasm.LogErrorf("error decoding plugin configuration: %v", err)
		return types.ActionContinue
	}

	ctx.dispatchHttpCall(v)
	return types.ActionContinue
}

func (ctx *httpContext) httpCallback(numHeaders int, bodySize int, numTrailers int) {
	hs, err := proxywasm.GetHttpCallResponseHeaders()
	if err != nil {
		proxywasm.LogErrorf("callback err: %v", err)
		return
	}

	var status int
	for _, h := range hs {
		if h[0] == ":status" {
			status, _ = strconv.Atoi(h[1])
		}

		if _, ok := ctx.pluginCtx.upstreamHeaders[h[0]]; ok {
			err := proxywasm.ReplaceHttpRequestHeader(h[0], h[1])
			if err != nil {
				proxywasm.LogErrorf("set header failed: %v", err)
			}
		}
	}

	if status >= 300 {
		chs := [][2]string{}
		for _, h := range hs {
			if _, ok := ctx.pluginCtx.clientHeaders[h[0]]; ok {
				chs = append(chs, [2]string{h[0], h[1]})
			}
		}

		if err := proxywasm.SendHttpResponse(403, chs, nil, -1); err != nil {
			proxywasm.LogErrorf("send http failed: %v", err)
			return
		}
	}
}
