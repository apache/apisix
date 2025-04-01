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

FROM ubuntu:24.04

RUN apt update && export DEBIAN_FRONTEND=noninteractive \
    && apt install -y sudo git make gcc tini

COPY Makefile .requirements apisix-master-0.rockspec ./
COPY utils/install-dependencies.sh utils/linux-install-luarocks.sh utils/

RUN make install-runtime

RUN cpanm --notest Test::Nginx IPC::Run > build.log 2>&1 || (cat build.log && exit 1)

ARG ETCD_VER=v3.5.17
ARG BUILDARCH
RUN curl -L https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-${BUILDARCH}.tar.gz -o /tmp/etcd-${ETCD_VER}-linux-${BUILDARCH}.tar.gz \
    && mkdir -p /tmp/etcd-download-test \
    && tar xzvf /tmp/etcd-${ETCD_VER}-linux-${BUILDARCH}.tar.gz -C /tmp/etcd-download-test --strip-components=1 \
    && mv /tmp/etcd-download-test/etcdctl /usr/bin \
    && rm -rf /tmp/*

ENTRYPOINT [ "tini", "--" ]
