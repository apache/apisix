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
package org.apache.dubbo.backend.provider;

import org.apache.dubbo.backend.DemoService;

import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.TimeUnit;
import java.lang.InterruptedException;

public class DemoServiceImpl implements DemoService {
    @Override
    public Map<String, Object> hello(Map<String, Object> context) {
        Map<String, Object> ret = new HashMap<String, Object>();
        ret.put("body", "dubbo success\n");
        ret.put("status", "200");

        for (Map.Entry<String, Object> entry : context.entrySet()) {
            System.out.println("Key = " + entry.getKey() + ", Value = " + entry.getValue());
            if (entry.getKey().startsWith("extra-arg")) {
                ret.put("Got-" + entry.getKey(), entry.getValue());
            }
        }

        return ret;
    }

    @Override
    public Map<String, Object> fail(Map<String, Object> context) {
        Map<String, Object> ret = new HashMap<String, Object>();
        ret.put("body", "dubbo fail\n");
        ret.put("status", "503");
        return ret;
    }

    @Override
    public Map<String, Object> timeout(Map<String, Object> context) {
        Map<String, Object> ret = new HashMap<String, Object>();
        try {
            TimeUnit.MILLISECONDS.sleep(500);
        } catch (InterruptedException ex) {}
        ret.put("body", "dubbo fail\n");
        ret.put("status", "503");
        return ret;
    }
}
