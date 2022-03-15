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

/*
#cgo LDFLAGS: -shared
#include <stdlib.h>

extern void ngx_http_lua_ffi_shdict_store(void *zone, int op,
    const unsigned char *key, size_t key_len,
	int value_type,
    const unsigned char *str_value_buf, size_t str_value_len,
    double num_value, long exptime, int user_flags, char **errmsg,
    int *forcible);
*/
import "C"

import (
	"fmt"
	"time"
	"unsafe"
)

func main() {
}


//export initial
func initial(zone unsafe.Pointer) {
	time.Sleep(time.Second)
	value := fmt.Sprintf(`{
"status": 1,
"update_time": 1647250524,
"create_time": 1646972532,
"uri": "/hello",
"priority": 0,
"id": "1",
"upstream": {
	"nodes": [
		{
			"port": 80,
			"priority": 0,
			"host": "127.0.0.1",
			"weight": 1
		}
	],
	"type": "roundrobin",
	"hash_on": "vars",
	"pass_host": "pass",
	"scheme": "http"
}
}`)

	writeShdict(zone, "/apisix/routes/1", value)
}

func writeShdict(zone unsafe.Pointer, key, value string) {
	var keyCStr = C.CString(key)
	defer C.free(unsafe.Pointer(keyCStr))
	var keyLen = C.size_t(len(key))

	var valueCStr = C.CString(value)
	defer C.free(unsafe.Pointer(valueCStr))
	var valueLen = C.size_t(len(value))

	errMsgBuf := make([]*C.char, 1)
	var forcible = 0

	C.ngx_http_lua_ffi_shdict_store(zone, 0x0004,
		(*C.uchar)(unsafe.Pointer(keyCStr)), keyLen,
		4,
		(*C.uchar)(unsafe.Pointer(valueCStr)), valueLen,
		0, 0, 0,
		(**C.char)(unsafe.Pointer(&errMsgBuf[0])),
		(*C.int)(unsafe.Pointer(&forcible)),
	)
}
