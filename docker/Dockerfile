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

FROM api7/apisix-base:dev AS build

ARG ENABLE_PROXY=false

ENV DEBIAN_FRONTEND noninteractive

COPY ./apisix /usr/local/apisix/apisix
COPY ./conf /usr/local/apisix/conf
COPY ./bin/apisix /usr/bin/apisix
COPY ./rockspec/apisix-master-0.rockspec /usr/local/apisix/rockspec/apisix-master-0.rockspec
COPY ./utils/linux-install-luarocks.sh /usr/local/apisix/linux-install-luarocks.sh

WORKDIR /usr/local/apisix

SHELL ["/bin/bash", "-c"]

RUN set -x \
    && (test "${ENABLE_PROXY}" != "true" || /bin/sed -i 's,http://deb.debian.org,http://mirrors.aliyun.com,g' /etc/apt/sources.list) \
    && apt-get -y update --fix-missing \
    && apt-get install -y curl \
        gawk \
        git \
        libldap2-dev \
        liblua5.1-0-dev \
        lua5.1 \
        sudo \
        unzip \
        wget \
        make \
        libssl-dev \
    && curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \ 
    && source "$HOME/.cargo/env" \
    && bash ./linux-install-luarocks.sh \
    && luarocks config variables.OPENSSL_INCDIR /usr/include/ \ 
    && luarocks config variables.PCRE_DIR /usr/local/openresty/pcre \
    && luarocks install rockspec/apisix-master-0.rockspec --tree=/usr/local/apisix/deps --deps-only \
    && mkdir /usr/local/apisix/logs && touch /usr/local/apisix/logs/error.log && touch /usr/local/apisix/logs/access.log

ENV PATH=$PATH:/usr/local/openresty-debug/luajit/bin:/usr/local/openresty-debug/nginx/sbin:/usr/local/openresty-debug/bin

EXPOSE 9080 9443

COPY ./docker/docker-entrypoint.sh /docker-entrypoint.sh

ENTRYPOINT ["/docker-entrypoint.sh"]

CMD ["docker-start"]

STOPSIGNAL SIGQUIT
