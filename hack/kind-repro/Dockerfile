#
# Local repro image: builds APISIX from this repo's source, optionally with
# the local apache/apisix#13888 patch (hack/patches/lua-resty-healthcheck-13888.patch)
# applied to the vendored lua-resty-healthcheck-api7 rock.
#
# Build stock:   docker build -f hack/kind-repro/Dockerfile -t apisix-repro:stock .
# Build patched: docker build -f hack/kind-repro/Dockerfile --build-arg APPLY_PATCH=true -t apisix-repro:patched .
# Build cold-start gate (reconcile + probed-gate patches, mollie-health-check
# plugin included): docker build -f hack/kind-repro/Dockerfile
#   --build-arg APPLY_PATCH=true --build-arg APPLY_PROBED_GATE_PATCH=true
#   -t apisix-repro:coldstart-gate .
#
# Adapted from docker/debian-dev/Dockerfile (this repo's own source-build
# Dockerfile) -- not editing that file directly since it's a tracked,
# upstream-shared file and this is a throwaway local repro image.
FROM debian:bullseye-slim AS build

ARG APPLY_PATCH=false
# Stacks on APPLY_PATCH -- the probed-gate patch's diff assumes the #13888
# reconcile patch is already applied (see hack/patches/lua-resty-healthcheck-
# probed-gate.patch's own header). Applying this without APPLY_PATCH=true
# will fail to apply cleanly; that failure is intentional, not worth guarding.
ARG APPLY_PROBED_GATE_PATCH=false
# TEST-ONLY: force real apache/apisix#13888-style dropped worker_events
# broadcasts by shrinking the resty.events per-worker queue (default 10,240,
# not exposed as an apisix config knob) down to 2 -- a couple of rapid
# health-state transitions is then enough to hit queue.lua's real
# "queue overflow" push() failure, which broker.lua just logs and drops
# (no retry/redelivery). Never for production images.
ARG SHRINK_EVENTS_QUEUE=false

ENV DEBIAN_FRONTEND=noninteractive
ENV ENV_INST_LUADIR=/usr/local/apisix

COPY . /apisix
WORKDIR /apisix

RUN set -x \
    && apt-get -y update --fix-missing \
    && apt-get install -y \
        make \
        git \
        sudo \
        ca-certificates \
        curl \
        gcc \
        g++ \
        cmake \
        libyaml-dev \
        libxml2-dev \
        libxslt1-dev \
        pkg-config \
        libssl-dev \
        zlib1g-dev \
        patch \
    && rm -rf deps \
    && make deps \
    && if [ "$APPLY_PATCH" = "true" ]; then \
         patch -p3 -d deps/share/lua/5.1/resty < hack/patches/lua-resty-healthcheck-13888.patch; \
       fi \
    && if [ "$APPLY_PROBED_GATE_PATCH" = "true" ]; then \
         patch -p3 -d deps/share/lua/5.1/resty < hack/patches/lua-resty-healthcheck-probed-gate.patch; \
       fi \
    && if [ "$SHRINK_EVENTS_QUEUE" = "true" ]; then \
         sed -i 's/listening = listening,.*/&\n        max_queue_len = 2,/' apisix/events.lua && \
         grep -n "max_queue_len" apisix/events.lua; \
       fi \
    && mkdir -p ${ENV_INST_LUADIR} \
    && cp -r deps ${ENV_INST_LUADIR} \
    && make install

FROM debian:bullseye-slim

RUN apt-get -y update --fix-missing \
    && apt-get install -y libldap2-dev libyaml-0-2 libxml2 libxslt1.1 curl \
    && apt-get remove --purge --auto-remove -y

COPY --from=build /usr/local/apisix /usr/local/apisix
COPY --from=build /usr/local/openresty /usr/local/openresty
COPY --from=build /usr/bin/apisix /usr/bin/apisix

# Mollie's readiness plugin (edge-app), staged into this repo's build context
# at hack/kind-repro/plugin/ -- harmless if unused (only loaded if a config's
# `plugins:` list names it).
COPY hack/kind-repro/plugin/mollie-health-check.lua /usr/local/apisix/apisix/plugins/mollie-health-check.lua

ENV PATH=$PATH:/usr/local/openresty/luajit/bin:/usr/local/openresty/nginx/sbin:/usr/local/openresty/bin

WORKDIR /usr/local/apisix

RUN ln -sf /dev/stdout /usr/local/apisix/logs/access.log \
    && ln -sf /dev/stderr /usr/local/apisix/logs/error.log

EXPOSE 9080 9443

COPY docker/debian-dev/docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["docker-start"]
STOPSIGNAL SIGQUIT
