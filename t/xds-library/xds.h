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
#ifndef XDS_H
#define XDS_H
#include <dlfcn.h>
#include <stdlib.h>


void ngx_lua_ffi_shdict_store(void *zone, int op,
    const unsigned char *key, size_t key_len,
    int value_type,
    const unsigned char *str_value_buf, size_t str_value_len,
    double num_value, long exptime, int user_flags, char **errmsg,
    int *forcible)
{
    static void* dlhandle;
    static void (*fp)(void *zone, int op,
                      const unsigned char *key, size_t key_len,
                      int value_type,
                      const unsigned char *str_value_buf, size_t str_value_len,
                      double num_value, long exptime, int user_flags, char **errmsg,
                      int *forcible);

    if (!dlhandle) {
        dlhandle = dlopen(NULL, RTLD_NOW);
    }
    if (!dlhandle) {
        return;
    }

    fp = dlsym(dlhandle, "ngx_http_lua_ffi_shdict_store");
    if (!fp) {
        fp = dlsym(dlhandle, "ngx_meta_lua_ffi_shdict_store");
    }

    fp(zone, op, key, key_len, value_type, str_value_buf, str_value_len,
       num_value, exptime, user_flags, errmsg, forcible);
}


#endif // XDS_H
