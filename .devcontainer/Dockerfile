# See here for image contents: https://github.com/microsoft/vscode-dev-containers/tree/v0.245.0/containers/debian/.devcontainer/base.Dockerfile

# [Choice] Debian version (use bullseye on local arm64/Apple Silicon): bullseye, buster
ARG VARIANT="buster"
FROM mcr.microsoft.com/vscode/devcontainers/base:0-${VARIANT}

# Update user's uid based on sent variable
# It seems it won't work on macos (with podman or rancher desktop) without this
ARG USERNAME=vscode

COPY .devcontainer/change-uid.sh /usr/local/bin/change-uid.sh
RUN change-uid.sh

# ** [Optional] Uncomment this section to install additional packages. **
# RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
#     && apt-get -y install --no-install-recommends <your-package-list-here>
RUN apt-get update && apt-get install cpanminus make luajit patch -y

WORKDIR /build
COPY utils ./utils
RUN ./utils/install-dependencies.sh
RUN luarocks install luacheck

RUN mkdir /workspaces && chown vscode: /workspaces
WORKDIR /workspaces
USER vscode

RUN mkdir -p /home/vscode/.ssh && ssh-keyscan github.com > /home/vscode/.ssh/known_hosts
RUN git clone https://github.com/openresty/test-nginx && sudo cpanm ./test-nginx
ENV PATH=$PATH:/usr/local/openresty/nginx/sbin
