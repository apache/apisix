---
title: 基于环境变量进行配置文件切换
---

<!--
#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
-->

配置之所以从代码中提取出来，就是为了更好适应变化。通常我们的应用都有开发环境、生产环境等不同运行环境，这些环境下应用的一些配置肯定会有不同，比如：配置中心的地址等。

如果把所有环境的配置都放在同一个文件里，非常不好管理，我们接到新需求后，在开发环境进行开发时，需要将配置文件中的参数都改成开发环境的，提交代码时还要改回去，这样改来改去非常容易出错。

上述问题的解决办法就是通过环境变量来区分当前运行环境，并通过环境变量来切换不同配置文件。APISIX 中对应的环境变量就是：`APISIX_PROFILE`。

在没有设置`APISIX_PROFILE` 时，默认使用以下三个配置文件：

* conf/config.yaml
* conf/apisix.yaml
* conf/debug.yaml

如果设置了`APISIX_PROFILE`的值为`prod`，则使用以下三个配置文件：

* conf/config-prod.yaml
* conf/apisix-prod.yaml
* conf/debug-prod.yaml

通过这种方式虽然会增加配置文件的数量，但可以独立管理，再配置git等版本管理工具，还能更好实现版本管理。
