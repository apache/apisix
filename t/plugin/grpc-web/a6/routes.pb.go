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

type Empty struct {
	XXX_NoUnkeyedLiteral struct{} `json:"-"`
	XXX_unrecognized     []byte   `json:"-"`
	XXX_sizecache        int32    `json:"-"`
}

func (m *Empty) Reset()         { *m = Empty{} }
func (m *Empty) String() string { return proto.CompactTextString(m) }
func (*Empty) ProtoMessage()    {}
func (*Empty) Descriptor() ([]byte, []int) {
	return fileDescriptor_078f480fb67d0ab3, []int{0}
}

func (m *Empty) XXX_Unmarshal(b []byte) error {
	return xxx_messageInfo_Empty.Unmarshal(m, b)
}
func (m *Empty) XXX_Marshal(b []byte, deterministic bool) ([]byte, error) {
	return xxx_messageInfo_Empty.Marshal(b, m, deterministic)
}
func (m *Empty) XXX_Merge(src proto.Message) {
	xxx_messageInfo_Empty.Merge(m, src)
}
func (m *Empty) XXX_Size() int {
	return xxx_messageInfo_Empty.Size(m)
}
func (m *Empty) XXX_DiscardUnknown() {
	xxx_messageInfo_Empty.DiscardUnknown(m)
}

var xxx_messageInfo_Empty proto.InternalMessageInfo

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
	return fileDescriptor_078f480fb67d0ab3, []int{1}
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

type Request struct {
	Id                   string   `protobuf:"bytes,1,opt,name=id,proto3" json:"id,omitempty"`
	Route                *Route   `protobuf:"bytes,2,opt,name=route,proto3" json:"route,omitempty"`
	XXX_NoUnkeyedLiteral struct{} `json:"-"`
	XXX_unrecognized     []byte   `json:"-"`
	XXX_sizecache        int32    `json:"-"`
}

func (m *Request) Reset()         { *m = Request{} }
func (m *Request) String() string { return proto.CompactTextString(m) }
func (*Request) ProtoMessage()    {}
func (*Request) Descriptor() ([]byte, []int) {
	return fileDescriptor_078f480fb67d0ab3, []int{2}
}

func (m *Request) XXX_Unmarshal(b []byte) error {
	return xxx_messageInfo_Request.Unmarshal(m, b)
}
func (m *Request) XXX_Marshal(b []byte, deterministic bool) ([]byte, error) {
	return xxx_messageInfo_Request.Marshal(b, m, deterministic)
}
func (m *Request) XXX_Merge(src proto.Message) {
	xxx_messageInfo_Request.Merge(m, src)
}
func (m *Request) XXX_Size() int {
	return xxx_messageInfo_Request.Size(m)
}
func (m *Request) XXX_DiscardUnknown() {
	xxx_messageInfo_Request.DiscardUnknown(m)
}

var xxx_messageInfo_Request proto.InternalMessageInfo

func (m *Request) GetId() string {
	if m != nil {
		return m.Id
	}
	return ""
}

func (m *Request) GetRoute() *Route {
	if m != nil {
		return m.Route
	}
	return nil
}

type Response struct {
	Status               bool              `protobuf:"varint,1,opt,name=status,proto3" json:"status,omitempty"`
	Route                *Route            `protobuf:"bytes,2,opt,name=route,proto3" json:"route,omitempty"`
	Routes               map[string]*Route `protobuf:"bytes,3,rep,name=routes,proto3" json:"routes,omitempty" protobuf_key:"bytes,1,opt,name=key,proto3" protobuf_val:"bytes,2,opt,name=value,proto3"`
	XXX_NoUnkeyedLiteral struct{}          `json:"-"`
	XXX_unrecognized     []byte            `json:"-"`
	XXX_sizecache        int32             `json:"-"`
}

func (m *Response) Reset()         { *m = Response{} }
func (m *Response) String() string { return proto.CompactTextString(m) }
func (*Response) ProtoMessage()    {}
func (*Response) Descriptor() ([]byte, []int) {
	return fileDescriptor_078f480fb67d0ab3, []int{3}
}

func (m *Response) XXX_Unmarshal(b []byte) error {
	return xxx_messageInfo_Response.Unmarshal(m, b)
}
func (m *Response) XXX_Marshal(b []byte, deterministic bool) ([]byte, error) {
	return xxx_messageInfo_Response.Marshal(b, m, deterministic)
}
func (m *Response) XXX_Merge(src proto.Message) {
	xxx_messageInfo_Response.Merge(m, src)
}
func (m *Response) XXX_Size() int {
	return xxx_messageInfo_Response.Size(m)
}
func (m *Response) XXX_DiscardUnknown() {
	xxx_messageInfo_Response.DiscardUnknown(m)
}

var xxx_messageInfo_Response proto.InternalMessageInfo

func (m *Response) GetStatus() bool {
	if m != nil {
		return m.Status
	}
	return false
}

func (m *Response) GetRoute() *Route {
	if m != nil {
		return m.Route
	}
	return nil
}

func (m *Response) GetRoutes() map[string]*Route {
	if m != nil {
		return m.Routes
	}
	return nil
}

func init() {
	proto.RegisterType((*Empty)(nil), "a6.Empty")
	proto.RegisterType((*Route)(nil), "a6.Route")
	proto.RegisterType((*Request)(nil), "a6.Request")
	proto.RegisterType((*Response)(nil), "a6.Response")
	proto.RegisterMapType((map[string]*Route)(nil), "a6.Response.RoutesEntry")
}

func init() { proto.RegisterFile("routes.proto", fileDescriptor_078f480fb67d0ab3) }

var fileDescriptor_078f480fb67d0ab3 = []byte{
	// 307 bytes of a gzipped FileDescriptorProto
	0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0xff, 0x84, 0x92, 0x4f, 0x4b, 0xf3, 0x40,
	0x10, 0x87, 0xdf, 0x24, 0x6f, 0xd2, 0x76, 0x52, 0x44, 0xe6, 0x20, 0xa1, 0x17, 0xcb, 0x4a, 0xa1,
	0xa7, 0x54, 0x2a, 0x14, 0xa9, 0x27, 0xc5, 0x5a, 0xbc, 0xae, 0x78, 0xf1, 0xb6, 0x9a, 0x81, 0x06,
	0xf3, 0xcf, 0xec, 0x26, 0x90, 0xcf, 0xe6, 0xc7, 0xf2, 0x0b, 0x48, 0x26, 0x39, 0x14, 0x14, 0x73,
	0x9b, 0x3c, 0x79, 0xe6, 0x37, 0x93, 0x21, 0x30, 0x2d, 0xf3, 0xca, 0x90, 0x0e, 0x8b, 0x32, 0x37,
	0x39, 0xda, 0x6a, 0x23, 0x46, 0xe0, 0xee, 0xd2, 0xc2, 0x34, 0x62, 0x05, 0xae, 0x6c, 0x5f, 0x22,
	0xc2, 0xff, 0x4c, 0xa5, 0x14, 0x58, 0x73, 0x6b, 0x39, 0x91, 0x5c, 0xb7, 0xac, 0x50, 0xe6, 0x10,
	0xd8, 0x1d, 0x6b, 0x6b, 0xb1, 0x85, 0x91, 0xa4, 0x8f, 0x8a, 0xb4, 0xc1, 0x13, 0xb0, 0xe3, 0xa8,
	0x6f, 0xb0, 0xe3, 0x08, 0xcf, 0xc1, 0xe5, 0x41, 0xec, 0xfb, 0xeb, 0x49, 0xa8, 0x36, 0x21, 0x87,
	0xcb, 0x8e, 0x8b, 0x4f, 0x0b, 0xc6, 0x92, 0x74, 0x91, 0x67, 0x9a, 0xf0, 0x0c, 0x3c, 0x6d, 0x94,
	0xa9, 0x34, 0x27, 0x8c, 0x65, 0xff, 0x34, 0x98, 0x82, 0x97, 0xe0, 0x75, 0xdf, 0x13, 0x38, 0x73,
	0x67, 0xe9, 0xaf, 0x03, 0x36, 0xfa, 0xd8, 0x4e, 0xd5, 0xbb, 0xcc, 0x94, 0x8d, 0xec, 0xbd, 0xd9,
	0x3d, 0xf8, 0x47, 0x18, 0x4f, 0xc1, 0x79, 0xa7, 0xa6, 0x5f, 0xbc, 0x2d, 0xdb, 0x99, 0xb5, 0x4a,
	0xaa, 0xdf, 0x66, 0x32, 0xdf, 0xda, 0xd7, 0xd6, 0xfa, 0xcb, 0x82, 0x29, 0xc3, 0x27, 0x2a, 0xeb,
	0xf8, 0x8d, 0x70, 0x01, 0xe3, 0x87, 0xa4, 0xd2, 0x87, 0xdb, 0x24, 0x41, 0x6e, 0xe1, 0x93, 0xce,
	0xa6, 0xc7, 0xfb, 0x88, 0x7f, 0x78, 0x01, 0xde, 0x9e, 0xcc, 0x80, 0x24, 0xc0, 0xd9, 0x93, 0x41,
	0xbf, 0xc3, 0x7c, 0xdf, 0x1f, 0xce, 0x02, 0xbc, 0xc7, 0x4c, 0x53, 0x39, 0xac, 0x3d, 0x17, 0x91,
	0x32, 0x34, 0xa8, 0x49, 0x4a, 0xf3, 0xfa, 0x6f, 0xed, 0x6e, 0xf4, 0xe2, 0x86, 0xab, 0x1b, 0xb5,
	0x79, 0xf5, 0xf8, 0xef, 0xb9, 0xfa, 0x0e, 0x00, 0x00, 0xff, 0xff, 0xba, 0xd4, 0xb5, 0x13, 0x4d,
	0x02, 0x00, 0x00,
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
	FlushAll(ctx context.Context, in *Empty, opts ...grpc.CallOption) (*Response, error)
	GetAll(ctx context.Context, in *Empty, opts ...grpc.CallOption) (*Response, error)
	Get(ctx context.Context, in *Request, opts ...grpc.CallOption) (*Response, error)
	Insert(ctx context.Context, in *Request, opts ...grpc.CallOption) (*Response, error)
	Update(ctx context.Context, in *Request, opts ...grpc.CallOption) (*Response, error)
	Remove(ctx context.Context, in *Request, opts ...grpc.CallOption) (*Response, error)
}

type routeServiceClient struct {
	cc *grpc.ClientConn
}

func NewRouteServiceClient(cc *grpc.ClientConn) RouteServiceClient {
	return &routeServiceClient{cc}
}

func (c *routeServiceClient) FlushAll(ctx context.Context, in *Empty, opts ...grpc.CallOption) (*Response, error) {
	out := new(Response)
	err := c.cc.Invoke(ctx, "/a6.RouteService/FlushAll", in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

func (c *routeServiceClient) GetAll(ctx context.Context, in *Empty, opts ...grpc.CallOption) (*Response, error) {
	out := new(Response)
	err := c.cc.Invoke(ctx, "/a6.RouteService/GetAll", in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

func (c *routeServiceClient) Get(ctx context.Context, in *Request, opts ...grpc.CallOption) (*Response, error) {
	out := new(Response)
	err := c.cc.Invoke(ctx, "/a6.RouteService/Get", in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

func (c *routeServiceClient) Insert(ctx context.Context, in *Request, opts ...grpc.CallOption) (*Response, error) {
	out := new(Response)
	err := c.cc.Invoke(ctx, "/a6.RouteService/Insert", in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

func (c *routeServiceClient) Update(ctx context.Context, in *Request, opts ...grpc.CallOption) (*Response, error) {
	out := new(Response)
	err := c.cc.Invoke(ctx, "/a6.RouteService/Update", in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

func (c *routeServiceClient) Remove(ctx context.Context, in *Request, opts ...grpc.CallOption) (*Response, error) {
	out := new(Response)
	err := c.cc.Invoke(ctx, "/a6.RouteService/Remove", in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

// RouteServiceServer is the server API for RouteService service.
type RouteServiceServer interface {
	FlushAll(context.Context, *Empty) (*Response, error)
	GetAll(context.Context, *Empty) (*Response, error)
	Get(context.Context, *Request) (*Response, error)
	Insert(context.Context, *Request) (*Response, error)
	Update(context.Context, *Request) (*Response, error)
	Remove(context.Context, *Request) (*Response, error)
}

// UnimplementedRouteServiceServer can be embedded to have forward compatible implementations.
type UnimplementedRouteServiceServer struct {
}

func (*UnimplementedRouteServiceServer) FlushAll(ctx context.Context, req *Empty) (*Response, error) {
	return nil, status.Errorf(codes.Unimplemented, "method FlushAll not implemented")
}
func (*UnimplementedRouteServiceServer) GetAll(ctx context.Context, req *Empty) (*Response, error) {
	return nil, status.Errorf(codes.Unimplemented, "method GetAll not implemented")
}
func (*UnimplementedRouteServiceServer) Get(ctx context.Context, req *Request) (*Response, error) {
	return nil, status.Errorf(codes.Unimplemented, "method Get not implemented")
}
func (*UnimplementedRouteServiceServer) Insert(ctx context.Context, req *Request) (*Response, error) {
	return nil, status.Errorf(codes.Unimplemented, "method Insert not implemented")
}
func (*UnimplementedRouteServiceServer) Update(ctx context.Context, req *Request) (*Response, error) {
	return nil, status.Errorf(codes.Unimplemented, "method Update not implemented")
}
func (*UnimplementedRouteServiceServer) Remove(ctx context.Context, req *Request) (*Response, error) {
	return nil, status.Errorf(codes.Unimplemented, "method Remove not implemented")
}

func RegisterRouteServiceServer(s *grpc.Server, srv RouteServiceServer) {
	s.RegisterService(&_RouteService_serviceDesc, srv)
}

func _RouteService_FlushAll_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	in := new(Empty)
	if err := dec(in); err != nil {
		return nil, err
	}
	if interceptor == nil {
		return srv.(RouteServiceServer).FlushAll(ctx, in)
	}
	info := &grpc.UnaryServerInfo{
		Server:     srv,
		FullMethod: "/a6.RouteService/FlushAll",
	}
	handler := func(ctx context.Context, req interface{}) (interface{}, error) {
		return srv.(RouteServiceServer).FlushAll(ctx, req.(*Empty))
	}
	return interceptor(ctx, in, info, handler)
}

func _RouteService_GetAll_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	in := new(Empty)
	if err := dec(in); err != nil {
		return nil, err
	}
	if interceptor == nil {
		return srv.(RouteServiceServer).GetAll(ctx, in)
	}
	info := &grpc.UnaryServerInfo{
		Server:     srv,
		FullMethod: "/a6.RouteService/GetAll",
	}
	handler := func(ctx context.Context, req interface{}) (interface{}, error) {
		return srv.(RouteServiceServer).GetAll(ctx, req.(*Empty))
	}
	return interceptor(ctx, in, info, handler)
}

func _RouteService_Get_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	in := new(Request)
	if err := dec(in); err != nil {
		return nil, err
	}
	if interceptor == nil {
		return srv.(RouteServiceServer).Get(ctx, in)
	}
	info := &grpc.UnaryServerInfo{
		Server:     srv,
		FullMethod: "/a6.RouteService/Get",
	}
	handler := func(ctx context.Context, req interface{}) (interface{}, error) {
		return srv.(RouteServiceServer).Get(ctx, req.(*Request))
	}
	return interceptor(ctx, in, info, handler)
}

func _RouteService_Insert_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	in := new(Request)
	if err := dec(in); err != nil {
		return nil, err
	}
	if interceptor == nil {
		return srv.(RouteServiceServer).Insert(ctx, in)
	}
	info := &grpc.UnaryServerInfo{
		Server:     srv,
		FullMethod: "/a6.RouteService/Insert",
	}
	handler := func(ctx context.Context, req interface{}) (interface{}, error) {
		return srv.(RouteServiceServer).Insert(ctx, req.(*Request))
	}
	return interceptor(ctx, in, info, handler)
}

func _RouteService_Update_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	in := new(Request)
	if err := dec(in); err != nil {
		return nil, err
	}
	if interceptor == nil {
		return srv.(RouteServiceServer).Update(ctx, in)
	}
	info := &grpc.UnaryServerInfo{
		Server:     srv,
		FullMethod: "/a6.RouteService/Update",
	}
	handler := func(ctx context.Context, req interface{}) (interface{}, error) {
		return srv.(RouteServiceServer).Update(ctx, req.(*Request))
	}
	return interceptor(ctx, in, info, handler)
}

func _RouteService_Remove_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	in := new(Request)
	if err := dec(in); err != nil {
		return nil, err
	}
	if interceptor == nil {
		return srv.(RouteServiceServer).Remove(ctx, in)
	}
	info := &grpc.UnaryServerInfo{
		Server:     srv,
		FullMethod: "/a6.RouteService/Remove",
	}
	handler := func(ctx context.Context, req interface{}) (interface{}, error) {
		return srv.(RouteServiceServer).Remove(ctx, req.(*Request))
	}
	return interceptor(ctx, in, info, handler)
}

var _RouteService_serviceDesc = grpc.ServiceDesc{
	ServiceName: "a6.RouteService",
	HandlerType: (*RouteServiceServer)(nil),
	Methods: []grpc.MethodDesc{
		{
			MethodName: "FlushAll",
			Handler:    _RouteService_FlushAll_Handler,
		},
		{
			MethodName: "GetAll",
			Handler:    _RouteService_GetAll_Handler,
		},
		{
			MethodName: "Get",
			Handler:    _RouteService_Get_Handler,
		},
		{
			MethodName: "Insert",
			Handler:    _RouteService_Insert_Handler,
		},
		{
			MethodName: "Update",
			Handler:    _RouteService_Update_Handler,
		},
		{
			MethodName: "Remove",
			Handler:    _RouteService_Remove_Handler,
		},
	},
	Streams:  []grpc.StreamDesc{},
	Metadata: "routes.proto",
}
