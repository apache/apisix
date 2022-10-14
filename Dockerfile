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

FROM ubuntu

# Install OpenResty x86
RUN apt update \
    && apt-get -y install --no-install-recommends wget curl gnupg ca-certificates sudo lsb-release vim \
    && wget -O - https://openresty.org/package/pubkey.gpg | sudo gpg --dearmor -o /usr/share/keyrings/openresty.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/openresty.gpg] http://openresty.org/package/ubuntu $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/openresty.list > /dev/null \
    && apt-get update \
    && apt install -y openresty openresty-openssl111-dev openresty-pcre-dev openresty-zlib-dev \
    && apt install -y unzip make gcc libldap2-dev libpcre3-dev git luajit \
    && ln -s /usr/bin/openresty /usr/bin/nginx

# Install Test::Nginx
RUN apt install -y cpanminus \
    && cpanm --notest Test::Nginx

# Install Luarocks
RUN wget https://raw.githubusercontent.com/apache/apisix/master/utils/linux-install-luarocks.sh \
    && bash linux-install-luarocks.sh

WORKDIR /usr/local/apisix
ENV PERL5LIB=.:$PERL5LIB
EXPOSE 80

CMD ["/bin/bash"]
