FROM ubuntu:24.04

RUN apt update && export DEBIAN_FRONTEND=noninteractive \
    && apt install -y sudo git make gcc

COPY Makefile .requirements apisix-master-0.rockspec ./
COPY utils/install-dependencies.sh utils/linux-install-luarocks.sh utils/

RUN make deps
