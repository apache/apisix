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
	context "context"
	fmt "fmt"
	proto "github.com/golang/protobuf/proto"
	grpc "google.golang.org/grpc"
	codes "google.golang.org/grpc/codes"
	status "google.golang.org/grpc/status"
	math "math"
)

// Reference imports to suppress errors if they are not otherwise used.
var _ = proto.Marshal
var _ = fmt.Errorf
var _ = math.Inf

// This is a compile-time assertion to ensure that this generated file
// is compatible with the proto package it is being compiled against.
// A compilation error at this line likely means your copy of the
// proto package needs to be updated.
const _ = proto.ProtoPackageIsVersion3 // please upgrade the proto package

type Query struct {
	Name                 string   `protobuf:"bytes,1,opt,name=name,proto3" json:"name,omitempty"`
	XXX_NoUnkeyedLiteral struct{} `json:"-"`
	XXX_unrecognized     []byte   `json:"-"`
	XXX_sizecache        int32    `json:"-"`
}

func (m *Query) Reset()         { *m = Query{} }
func (m *Query) String() string { return proto.CompactTextString(m) }
func (*Query) ProtoMessage()    {}
func (*Query) Descriptor() ([]byte, []int) {
	return fileDescriptor_0984d49a362b6b9f, []int{0}
}

func (m *Query) XXX_Unmarshal(b []byte) error {
	return xxx_messageInfo_Query.Unmarshal(m, b)
}
func (m *Query) XXX_Marshal(b []byte, deterministic bool) ([]byte, error) {
	return xxx_messageInfo_Query.Marshal(b, m, deterministic)
}
func (m *Query) XXX_Merge(src proto.Message) {
	xxx_messageInfo_Query.Merge(m, src)
}
func (m *Query) XXX_Size() int {
	return xxx_messageInfo_Query.Size(m)
}
func (m *Query) XXX_DiscardUnknown() {
	xxx_messageInfo_Query.DiscardUnknown(m)
}

var xxx_messageInfo_Query proto.InternalMessageInfo

func (m *Query) GetName() string {
	if m != nil {
		return m.Name
	}
	return ""
}

type Route struct {
	Name                 string   `protobuf:"bytes,1,opt,name=name,proto3" json:"name,omitempty"`
	Path                 string   `protobuf:"bytes,2,opt,name=path,proto3" json:"path,omitempty"`
	XXX_NoUnkeyedLiteral struct{} `json:"-"`
	XXX_unrecognized     []byte   `json:"-"`
	XXX_sizecache        int32    `json:"-"`
}

func (m *Route) Reset()         { *m = Route{} }
func (m *Route) String() string { return proto.CompactTextString(m) }
func (*Route) ProtoMessage()    {}
func (*Route) Descriptor() ([]byte, []int) {
	return fileDescriptor_0984d49a362b6b9f, []int{1}
}

func (m *Route) XXX_Unmarshal(b []byte) error {
	return xxx_messageInfo_Route.Unmarshal(m, b)
}
func (m *Route) XXX_Marshal(b []byte, deterministic bool) ([]byte, error) {
	return xxx_messageInfo_Route.Marshal(b, m, deterministic)
}
func (m *Route) XXX_Merge(src proto.Message) {
	xxx_messageInfo_Route.Merge(m, src)
}
func (m *Route) XXX_Size() int {
	return xxx_messageInfo_Route.Size(m)
}
func (m *Route) XXX_DiscardUnknown() {
	xxx_messageInfo_Route.DiscardUnknown(m)
}

var xxx_messageInfo_Route proto.InternalMessageInfo

func (m *Route) GetName() string {
	if m != nil {
		return m.Name
	}
	return ""
}

func (m *Route) GetPath() string {
	if m != nil {
		return m.Path
	}
	return ""
}

func init() {
	proto.RegisterType((*Query)(nil), "a6.Query")
	proto.RegisterType((*Route)(nil), "a6.Route")
}

func init() { proto.RegisterFile("route.proto", fileDescriptor_0984d49a362b6b9f) }

var fileDescriptor_0984d49a362b6b9f = []byte{
	// 149 bytes of a gzipped FileDescriptorProto
	0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0xff, 0xe2, 0xe2, 0x2e, 0xca, 0x2f, 0x2d,
	0x49, 0xd5, 0x2b, 0x28, 0xca, 0x2f, 0xc9, 0x17, 0x62, 0x4a, 0x34, 0x53, 0x92, 0xe6, 0x62, 0x0d,
	0x2c, 0x4d, 0x2d, 0xaa, 0x14, 0x12, 0xe2, 0x62, 0xc9, 0x4b, 0xcc, 0x4d, 0x95, 0x60, 0x54, 0x60,
	0xd4, 0xe0, 0x0c, 0x02, 0xb3, 0x95, 0xf4, 0xb9, 0x58, 0x83, 0x40, 0xea, 0xb1, 0x49, 0x82, 0xc4,
	0x0a, 0x12, 0x4b, 0x32, 0x24, 0x98, 0x20, 0x62, 0x20, 0xb6, 0x51, 0x24, 0x17, 0x0f, 0x58, 0x43,
	0x70, 0x6a, 0x51, 0x59, 0x66, 0x72, 0xaa, 0x90, 0x12, 0x17, 0x87, 0x7b, 0x6a, 0x09, 0xc4, 0x0c,
	0x4e, 0xbd, 0x44, 0x33, 0x3d, 0xb0, 0x5d, 0x52, 0x60, 0x26, 0x58, 0x54, 0x89, 0x41, 0x48, 0x95,
	0x8b, 0x13, 0xa6, 0xa6, 0x18, 0x97, 0x22, 0x03, 0x46, 0x27, 0xf6, 0x28, 0x56, 0x3d, 0x7d, 0xeb,
	0x44, 0xb3, 0x24, 0x36, 0xb0, 0xe3, 0x8d, 0x01, 0x01, 0x00, 0x00, 0xff, 0xff, 0x54, 0xf0, 0x73,
	0x63, 0xcb, 0x00, 0x00, 0x00,
}

// Reference imports to suppress errors if they are not otherwise used.
var _ context.Context
var _ grpc.ClientConn

// This is a compile-time assertion to ensure that this generated file
// is compatible with the grpc package it is being compiled against.
const _ = grpc.SupportPackageIsVersion4

// RouteServiceClient is the client API for RouteService service.
//
// For semantics around ctx use and closing/ending streaming RPCs, please refer to https://godoc.org/google.golang.org/grpc#ClientConn.NewStream.
type RouteServiceClient interface {
	GetRoute(ctx context.Context, in *Query, opts ...grpc.CallOption) (*Route, error)
	GetRoutes(ctx context.Context, in *Query, opts ...grpc.CallOption) (RouteService_GetRoutesClient, error)
}

type routeServiceClient struct {
	cc *grpc.ClientConn
}

func NewRouteServiceClient(cc *grpc.ClientConn) RouteServiceClient {
	return &routeServiceClient{cc}
}

func (c *routeServiceClient) GetRoute(ctx context.Context, in *Query, opts ...grpc.CallOption) (*Route, error) {
	out := new(Route)
	err := c.cc.Invoke(ctx, "/a6.RouteService/GetRoute", in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

func (c *routeServiceClient) GetRoutes(ctx context.Context, in *Query, opts ...grpc.CallOption) (RouteService_GetRoutesClient, error) {
	stream, err := c.cc.NewStream(ctx, &_RouteService_serviceDesc.Streams[0], "/a6.RouteService/GetRoutes", opts...)
	if err != nil {
		return nil, err
	}
	x := &routeServiceGetRoutesClient{stream}
	if err := x.ClientStream.SendMsg(in); err != nil {
		return nil, err
	}
	if err := x.ClientStream.CloseSend(); err != nil {
		return nil, err
	}
	return x, nil
}

type RouteService_GetRoutesClient interface {
	Recv() (*Route, error)
	grpc.ClientStream
}

type routeServiceGetRoutesClient struct {
	grpc.ClientStream
}

func (x *routeServiceGetRoutesClient) Recv() (*Route, error) {
	m := new(Route)
	if err := x.ClientStream.RecvMsg(m); err != nil {
		return nil, err
	}
	return m, nil
}

// RouteServiceServer is the server API for RouteService service.
type RouteServiceServer interface {
	GetRoute(context.Context, *Query) (*Route, error)
	GetRoutes(*Query, RouteService_GetRoutesServer) error
}

// UnimplementedRouteServiceServer can be embedded to have forward compatible implementations.
type UnimplementedRouteServiceServer struct {
}

func (*UnimplementedRouteServiceServer) GetRoute(ctx context.Context, req *Query) (*Route, error) {
	return nil, status.Errorf(codes.Unimplemented, "method GetRoute not implemented")
}
func (*UnimplementedRouteServiceServer) GetRoutes(req *Query, srv RouteService_GetRoutesServer) error {
	return status.Errorf(codes.Unimplemented, "method GetRoutes not implemented")
}

func RegisterRouteServiceServer(s *grpc.Server, srv RouteServiceServer) {
	s.RegisterService(&_RouteService_serviceDesc, srv)
}

func _RouteService_GetRoute_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	in := new(Query)
	if err := dec(in); err != nil {
		return nil, err
	}
	if interceptor == nil {
		return srv.(RouteServiceServer).GetRoute(ctx, in)
	}
	info := &grpc.UnaryServerInfo{
		Server:     srv,
		FullMethod: "/a6.RouteService/GetRoute",
	}
	handler := func(ctx context.Context, req interface{}) (interface{}, error) {
		return srv.(RouteServiceServer).GetRoute(ctx, req.(*Query))
	}
	return interceptor(ctx, in, info, handler)
}

func _RouteService_GetRoutes_Handler(srv interface{}, stream grpc.ServerStream) error {
	m := new(Query)
	if err := stream.RecvMsg(m); err != nil {
		return err
	}
	return srv.(RouteServiceServer).GetRoutes(m, &routeServiceGetRoutesServer{stream})
}

type RouteService_GetRoutesServer interface {
	Send(*Route) error
	grpc.ServerStream
}

type routeServiceGetRoutesServer struct {
	grpc.ServerStream
}

func (x *routeServiceGetRoutesServer) Send(m *Route) error {
	return x.ServerStream.SendMsg(m)
}

var _RouteService_serviceDesc = grpc.ServiceDesc{
	ServiceName: "a6.RouteService",
	HandlerType: (*RouteServiceServer)(nil),
	Methods: []grpc.MethodDesc{
		{
			MethodName: "GetRoute",
			Handler:    _RouteService_GetRoute_Handler,
		},
	},
	Streams: []grpc.StreamDesc{
		{
			StreamName:    "GetRoutes",
			Handler:       _RouteService_GetRoutes_Handler,
			ServerStreams: true,
		},
	},
	Metadata: "route.proto",
}
