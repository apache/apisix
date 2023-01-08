FROM api7/apisix-base:dev AS build

ARG ENABLE_PROXY=false

ENV DEBIAN_FRONTEND noninteractive

COPY . /apisix
WORKDIR /apisix

RUN set -x \
    && (test "${ENABLE_PROXY}" != "true" || /bin/sed -i 's,http://deb.debian.org,http://mirrors.aliyun.com,g' /etc/apt/sources.list) \
    && apt-get -y update --fix-missing \
    && apt-get install -y curl \
        gawk \
        git \
        libldap2-dev \
        liblua5.1-0-dev \
        lua5.1 \
        make \
        sudo \
        unzip \
        wget \
    && make deps \
    && make install

FROM api7/apisix-base:dev AS production-stage

COPY --from=build /usr/local/apisix /usr/local/apisix
COPY --from=build /usr/bin/apisix /usr/bin/apisix

ENV DEBIAN_FRONTEND noninteractive
RUN apt-get -y update --fix-missing \
    && apt-get install -y \
        libldap2-dev \
    && apt-get remove --purge --auto-remove -y

WORKDIR /usr/local/apisix

ENV PATH=$PATH:/usr/local/openresty-debug/luajit/bin:/usr/local/openresty-debug/nginx/sbin:/usr/local/openresty-debug/bin

EXPOSE 9080 9443

COPY ./docker-entrypoint.sh /docker-entrypoint.sh

ENTRYPOINT ["/docker-entrypoint.sh"]

CMD ["docker-start"]


STOPSIGNAL SIGQUIT