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
        libldap2-dev \
        liblua5.1-0-dev \
        lua5.1 \
        make \
        sudo \
        unzip \
        wget \
        gnupg2

RUN set -x \
    && bash utils/install-dependencies.sh \
    && make deps \
    && make install \
    && mv /usr/share/lua/5.1/apisix /usr/local/apisix \
    && mv /apisix/deps /usr/local/apisix

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

COPY ./docker/docker-entrypoint.sh /docker-entrypoint.sh

RUN chmod +x /docker-entrypoint.sh \
    # forward request and error logs to docker log collector
    && ln -sf /dev/stdout /usr/local/apisix/logs/access.log \
    && ln -sf /dev/stderr /usr/local/apisix/logs/error.log \
    && useradd -u 1001 apisix && chown -R apisix:apisix /usr/local/apisix

USER apisix

ENTRYPOINT ["/docker-entrypoint.sh"]

CMD ["docker-start"]

STOPSIGNAL SIGQUIT