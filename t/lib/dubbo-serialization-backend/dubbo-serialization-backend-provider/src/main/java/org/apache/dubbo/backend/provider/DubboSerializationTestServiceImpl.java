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

import org.apache.dubbo.backend.DubboSerializationTestService;
import org.apache.dubbo.backend.PoJo;
import org.apache.dubbo.common.utils.ReflectUtils;

import java.lang.reflect.Method;
import java.util.Arrays;
import java.util.concurrent.TimeUnit;

public class DubboSerializationTestServiceImpl implements DubboSerializationTestService {

    @Override
    public PoJo testPoJo(PoJo input) {
        return input;
    }

    @Override
    public PoJo[] testPoJos(PoJo[] input) {
        return input;
    }

    @Override
    public void testVoid() {
    }

    @Override
    public void testFailure() {
        throw new RuntimeException("testFailure");
    }

    @Override
    public void testTimeout() {
        try {
            TimeUnit.SECONDS.sleep(10);
        } catch (InterruptedException e) {
            throw new RuntimeException(e);
        }
    }

}
