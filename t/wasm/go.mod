module github.com/api7/wasm-nginx-module

go 1.15

require (
	github.com/tetratelabs/proxy-wasm-go-sdk v0.14.1-0.20210819090022-1e4e69881a31
	github.com/valyala/fastjson v1.6.3
)

//replace github.com/tetratelabs/proxy-wasm-go-sdk => ../proxy-wasm-go-sdk
