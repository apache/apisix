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
FROM debian:bullseye-slim AS build

ARG ENABLE_PROXY=false
ARG CODE_PATH

ENV DEBIAN_FRONTEND=noninteractive
ENV ENV_INST_LUADIR=/usr/local/apisix

COPY ${CODE_PATH} /apisix

WORKDIR /apisix

RUN set -x \
    && apt-get -y update --fix-missing \
    && apt-get install -y \
        make \
        git  \
        sudo \
        libyaml-dev \
    && ls -al \
    && make deps \
    && mkdir -p ${ENV_INST_LUADIR} \
    && cp -r deps ${ENV_INST_LUADIR} \
    && make install

FROM debian:bullseye-slim

ARG ENTRYPOINT_PATH=./docker-entrypoint.sh
ARG INSTALL_BROTLI=./install-brotli.sh
ARG CHECK_STANDALONE_CONFIG=./check_standalone_config.sh

# Install the runtime libyaml package
RUN apt-get -y update --fix-missing \
    && apt-get install -y libldap2-dev libyaml-0-2 \
    && apt-get remove --purge --auto-remove -y

COPY --from=build /usr/local/apisix /usr/local/apisix
COPY --from=build /usr/local/openresty /usr/local/openresty
COPY --from=build /usr/bin/apisix /usr/bin/apisix

COPY ${INSTALL_BROTLI} /install-brotli.sh
RUN chmod +x /install-brotli.sh \
    && cd / && ./install-brotli.sh && rm -rf /install-brotli.sh

ENV PATH=$PATH:/usr/local/openresty/luajit/bin:/usr/local/openresty/nginx/sbin:/usr/local/openresty/bin

WORKDIR /usr/local/apisix

RUN ln -sf /dev/stdout /usr/local/apisix/logs/access.log \
    && ln -sf /dev/stderr /usr/local/apisix/logs/error.log

EXPOSE 9080 9443

COPY ${ENTRYPOINT_PATH} /docker-entrypoint.sh
COPY ${CHECK_STANDALONE_CONFIG} /check_standalone_config.sh
RUN chmod +x /docker-entrypoint.sh /check_standalone_config.sh

ENTRYPOINT ["/docker-entrypoint.sh"]

CMD ["docker-start"]

STOPSIGNAL SIGQUIT
