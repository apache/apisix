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

package a6

import (
	"errors"
	"golang.org/x/net/context"

	uuid "github.com/satori/go.uuid"
)

type RouteServer struct {
	Routes map[string]*Route
}

func (rs *RouteServer) init() {
	if rs.Routes == nil {
		rs.Routes = make(map[string]*Route)
	}
}

func (rs *RouteServer) FlushAll(ctx context.Context, req *Empty) (*Response, error) {
	if rs.Routes != nil {
		rs.Routes = make(map[string]*Route)
	}
	return &Response{Routes: rs.Routes, Status: true}, nil
}

func (rs *RouteServer) GetAll(ctx context.Context, req *Empty) (*Response, error) {
	rs.init()
	return &Response{Routes: rs.Routes, Status: true}, nil
}

func (rs *RouteServer) Get(ctx context.Context, req *Request) (*Response, error) {
	rs.init()
	if len(req.Id) == 0 {
		return &Response{Status: false}, errors.New("route ID undefined")
	}

	if route, ok := rs.Routes[req.Id]; ok {
		return &Response{Status: true, Route: route}, nil
	}

	return &Response{Status: false}, errors.New("route not found")
}

func (rs *RouteServer) Insert(ctx context.Context, req *Request) (*Response, error) {
	rs.init()
	if len(req.Id) <= 0 {
		req.Id = uuid.NewV4().String()
	}
	rs.Routes[req.Id] = req.Route
	return &Response{Status: true, Routes: rs.Routes}, nil
}

func (rs *RouteServer) Update(ctx context.Context, req *Request) (*Response, error) {
	rs.init()
	if len(req.Id) == 0 {
		return &Response{Status: false}, errors.New("route ID undefined")
	}

	if _, ok := rs.Routes[req.Id]; ok {
		rs.Routes[req.Id] = req.Route
		return &Response{Status: true, Routes: rs.Routes}, nil
	}

	return &Response{Status: false}, errors.New("route not found")
}

func (rs *RouteServer) Remove(ctx context.Context, req *Request) (*Response, error) {
	rs.init()
	if len(req.Id) == 0 {
		return &Response{Status: false}, errors.New("route ID undefined")
	}

	if _, ok := rs.Routes[req.Id]; ok {
		delete(rs.Routes, req.Id)
		return &Response{Status: true, Routes: rs.Routes}, nil
	}

	return &Response{Status: false}, errors.New("route not found")
}
