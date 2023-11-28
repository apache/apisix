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

FROM eclipse-temurin:8

ENV SUFFIX_NUM=${SUFFIX_NUM:-1}
ENV NACOS_ADDR=${NACOS_ADDR:-127.0.0.1:8848}
ENV SERVICE_NAME=${SERVICE_NAME:-gateway-service}
ENV NAMESPACE=${NAMESPACE}
ENV GROUP=${GROUP:-DEFAULT_GROUP}

ADD https://raw.githubusercontent.com/api7/nacos-test-service/main/spring-nacos-1.0-SNAPSHOT.jar /app.jar

ENTRYPOINT ["java","-Djava.security.egd=file:/dev/./urandom","-jar","/app.jar",\
            "--suffix.num=${SUFFIX_NUM}","--spring.cloud.nacos.discovery.server-addr=${NACOS_ADDR}",\
            "--spring.application.name=${SERVICE_NAME}","--spring.cloud.nacos.discovery.group=${GROUP}",\
            "--spring.cloud.nacos.discovery.namespace=${NAMESPACE}"]
EXPOSE 18001
