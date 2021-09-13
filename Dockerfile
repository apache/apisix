ARG ENABLE_PROXY=true

FROM openresty/openresty:1.19.3.1-alpine-fat AS production-stage

ARG ENABLE_PROXY
ARG APISIX_PATH=.
COPY $APISIX_PATH ./apisix
RUN set -x \
    && echo  https://mirrors.aliyun.com/alpine/v3.13/main > /etc/apk/repositories \
    && echo  https://mirrors.aliyun.com/alpine/v3.13/community >> /etc/apk/repositories \
    # && apk add --no-cache --virtual .builddeps 
    && apk add --no-cache --virtual .builddeps \
    automake \
    autoconf \
    libtool \
    pkgconfig \
    cmake \
    git \
    pcre \
    pcre-dev \
    && cd apisix \
    && make deps \
    && cp -v bin/apisix /usr/bin/ \
    && mv ../apisix /usr/local/apisix \
    && apk del .builddeps build-base make unzip

FROM alpine:3.13 AS last-stage

ARG ENABLE_PROXY
# add runtime for Apache APISIX
RUN set -x \
    && echo  https://mirrors.aliyun.com/alpine/v3.13/main > /etc/apk/repositories \
    && echo  https://mirrors.aliyun.com/alpine/v3.13/community >> /etc/apk/repositories \
    && apk add --no-cache bash libstdc++ curl tzdata

WORKDIR /usr/local/apisix

COPY --from=production-stage /usr/local/openresty/ /usr/local/openresty/
COPY --from=production-stage /usr/local/apisix/ /usr/local/apisix/
COPY --from=production-stage /usr/bin/apisix /usr/bin/apisix

# forward request and error logs to docker log collector
RUN mkdir -p logs && touch logs/access.log && touch logs/error.log \
    && ln -sf /dev/stdout /usr/local/apisix/logs/access.log \
    && ln -sf /dev/stderr /usr/local/apisix/logs/error.log

ENV PATH=$PATH:/usr/local/openresty/luajit/bin:/usr/local/openresty/nginx/sbin:/usr/local/openresty/bin

EXPOSE 9080 9443

CMD ["sh", "-c", "/usr/bin/apisix init && /usr/bin/apisix init_etcd && /usr/local/openresty/bin/openresty -p /usr/local/apisix -g 'daemon off;'"]

STOPSIGNAL SIGQUIT