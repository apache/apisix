module github.com/api7/wasm-nginx-module

go 1.17

require (
	github.com/tetratelabs/proxy-wasm-go-sdk v0.16.0
	github.com/valyala/fastjson v1.6.3
)

//replace github.com/tetratelabs/proxy-wasm-go-sdk => ../proxy-wasm-go-sdk
