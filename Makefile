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

# Makefile basic env setting
.DEFAULT_GOAL := help
# add pipefail support for default shell
SHELL := /bin/bash -o pipefail


# Project basic setting
project_name           ?= apache-apisix
project_version        ?= latest
project_compose_ci     ?= ci/pod/docker-compose.yml
project_release_name   ?= $(project_name)-$(project_version)-src


# Hyperconverged Infrastructure
ENV_OS_NAME            ?= $(shell uname -s | tr '[:upper:]' '[:lower:]')
ENV_OS_ARCH            ?= $(shell uname -m | tr '[:upper:]' '[:lower:]')
ENV_APISIX             ?= $(CURDIR)/bin/apisix
ENV_GIT                ?= git
ENV_DOCKER             ?= docker
ENV_DOCKER_COMPOSE     ?= docker-compose --project-directory $(CURDIR) -p $(project_name) -f $(project_compose_ci)
ENV_NGINX              ?= nginx -p $(CURDIR) -c $(CURDIR)/conf/nginx.conf


# OSX archive `._` cache file
ifeq ($(ENV_OS_NAME), darwin)
	ENV_TAR ?= COPYFILE_DISABLE=1 tar
else
	ENV_TAR ?= tar
endif


# OLD VAR
INST_PREFIX ?= /usr
INST_LIBDIR ?= $(INST_PREFIX)/lib64/lua/5.1
INST_LUADIR ?= $(INST_PREFIX)/share/lua/5.1
INST_BINDIR ?= /usr/bin
INSTALL ?= install
OR_EXEC ?= $(shell which openresty || which nginx)
LUAROCKS ?= luarocks
LUAROCKS_VER ?= $(shell luarocks --version | grep -E -o  "luarocks [0-9]+.")
OR_PREFIX ?= $(shell $(OR_EXEC) -V 2>&1 | grep -Eo 'prefix=(.*)/nginx\s+' | grep -Eo '/.*/')
OPENSSL_PREFIX ?= $(addprefix $(OR_PREFIX), openssl)
HOMEBREW_PREFIX ?= /usr/local

# OpenResty 1.17.8 or higher version uses openssl111 as the openssl dirname.
ifeq ($(shell test -d $(addprefix $(OR_PREFIX), openssl111) && echo -n yes), yes)
	OPENSSL_PREFIX=$(addprefix $(OR_PREFIX), openssl111)
endif

ifeq ($(ENV_OS_NAME), darwin)
	ifeq ($(ENV_OS_ARCH), arm64)
		HOMEBREW_PREFIX=/opt/homebrew
	endif
	LUAROCKS=luarocks --lua-dir=$(HOMEBREW_PREFIX)/opt/lua@5.1
	ifeq ($(shell test -d $(HOMEBREW_PREFIX)/opt/openresty-openssl && echo yes), yes)
		OPENSSL_PREFIX=$(HOMEBREW_PREFIX)/opt/openresty-openssl
	endif
	ifeq ($(shell test -d $(HOMEBREW_PREFIX)/opt/openresty-openssl111 && echo yes), yes)
		OPENSSL_PREFIX=$(HOMEBREW_PREFIX)/opt/openresty-openssl111
	endif
endif

LUAROCKS_SERVER_OPT =
ifneq ($(LUAROCKS_SERVER), )
	LUAROCKS_SERVER_OPT = --server ${LUAROCKS_SERVER}
endif


# Makefile basic extension function
_color_red    =\E[1;31m
_color_green  =\E[1;32m
_color_yellow =\E[1;33m
_color_blue   =\E[1;34m
_color_wipe   =\E[0m


define func_echo_status
	printf "[%b info %b] %s\n" "$(_color_blue)" "$(_color_wipe)" $(1)
endef


define func_echo_warn_status
	printf "[%b info %b] %s\n" "$(_color_yellow)" "$(_color_wipe)" $(1)
endef


define func_echo_success_status
	printf "[%b info %b] %s\n" "$(_color_green)" "$(_color_wipe)" $(1)
endef


define func_check_folder
	if [[ ! -d $(1) ]]; then \
		mkdir -p $(1); \
		$(call func_echo_status, 'folder check -> create `$(1)`'); \
	else \
		$(call func_echo_success_status, 'folder check -> found `$(1)`'); \
	fi
endef


# Makefile target
.PHONY: runtime
runtime:
ifeq ($(OR_EXEC), )
ifeq ("$(wildcard /usr/local/openresty-debug/bin/openresty)", "")
	@echo "WARNING: OpenResty not found. You have to install OpenResty and add the binary file to PATH before install Apache APISIX."
	exit 1
else
	OR_EXEC=/usr/local/openresty-debug/bin/openresty
endif
endif


### help : Show Makefile rules
.PHONY: help
help:
	@$(call func_echo_success_status, "Makefile rules:")
	@echo
	@if [ '$(ENV_OS_NAME)' = 'darwin' ]; then \
		awk '{ if(match($$0, /^#{3}([^:]+):(.*)$$/)){ split($$0, res, ":"); gsub(/^#{3}[ ]*/, "", res[1]); _desc=$$0; gsub(/^#{3}([^:]+):[ \t]*/, "", _desc); printf("    make %-15s : %-10s\n", res[1], _desc) } }' Makefile; \
	else \
		awk '{ if(match($$0, /^\s*#{3}\s*([^:]+)\s*:\s*(.*)$$/, res)){ printf("    make %-15s : %-10s\n", res[1], res[2]) } }' Makefile; \
	fi
	@echo


### deps : Installation dependencies
.PHONY: deps
deps: runtime
ifeq ($(LUAROCKS_VER),luarocks 3.)
	mkdir -p ~/.luarocks
ifeq ($(shell whoami),root)
	$(LUAROCKS) config variables.OPENSSL_LIBDIR $(addprefix $(OPENSSL_PREFIX), /lib)
	$(LUAROCKS) config variables.OPENSSL_INCDIR $(addprefix $(OPENSSL_PREFIX), /include)
else
	$(LUAROCKS) config --local variables.OPENSSL_LIBDIR $(addprefix $(OPENSSL_PREFIX), /lib)
	$(LUAROCKS) config --local variables.OPENSSL_INCDIR $(addprefix $(OPENSSL_PREFIX), /include)
endif
	$(LUAROCKS) install rockspec/apisix-master-0.rockspec --tree=deps --only-deps --local $(LUAROCKS_SERVER_OPT)
else
	@echo "WARN: You're not using LuaRocks 3.x, please add the following items to your LuaRocks config file:"
	@echo "variables = {"
	@echo "    OPENSSL_LIBDIR=$(addprefix $(OPENSSL_PREFIX), /lib)"
	@echo "    OPENSSL_INCDIR=$(addprefix $(OPENSSL_PREFIX), /include)"
	@echo "}"
	$(LUAROCKS) install rockspec/apisix-master-0.rockspec --tree=deps --only-deps --local $(LUAROCKS_SERVER_OPT)
endif


### utils : Installation tools
.PHONY: utils
utils:
ifeq ("$(wildcard utils/lj-releng)", "")
	wget -P utils https://raw.githubusercontent.com/iresty/openresty-devel-utils/master/lj-releng
	chmod a+x utils/lj-releng
endif
ifeq ("$(wildcard utils/reindex)", "")
	wget -P utils https://raw.githubusercontent.com/iresty/openresty-devel-utils/master/reindex
	chmod a+x utils/reindex
endif


### lint : Lint source code
.PHONY: lint
lint: utils
	@$(call func_echo_status, "$@ -> [ Start ]")
	./utils/check-lua-code-style.sh
	./utils/check-test-code-style.sh
	@$(call func_echo_success_status, "$@ -> [ Done ]")


### init : Initialize the runtime environment
.PHONY: init
init: runtime
	@$(call func_echo_status, "$@ -> [ Start ]")
	$(ENV_APISIX) init
	$(ENV_APISIX) init_etcd
	@$(call func_echo_success_status, "$@ -> [ Done ]")


### run : Start the apisix server
.PHONY: run
run: runtime
	@$(call func_echo_status, "$@ -> [ Start ]")
	$(ENV_APISIX) start
	@$(call func_echo_success_status, "$@ -> [ Done ]")


### quit : Stop the apisix server, exit gracefully
.PHONY: quit
quit: runtime
	@$(call func_echo_status, "$@ -> [ Start ]")
	$(ENV_APISIX) quit
	@$(call func_echo_success_status, "$@ -> [ Done ]")


### stop : Stop the apisix server, exit immediately
.PHONY: stop
stop: runtime
	@$(call func_echo_status, "$@ -> [ Start ]")
	$(ENV_APISIX) stop
	@$(call func_echo_success_status, "$@ -> [ Done ]")


### verify : Verify the configuration of apisix server
.PHONY: verify
verify: runtime
	@$(call func_echo_status, "$@ -> [ Start ]")
	$(ENV_NGINX) -t
	@$(call func_echo_success_status, "$@ -> [ Done ]")


### clean : Remove generated files
.PHONY: clean
clean:
	@$(call func_echo_status, "$@ -> [ Start ]")
	rm -rf logs/
	@$(call func_echo_success_status, "$@ -> [ Done ]")


### reload : Reload the apisix server
.PHONY: reload
reload: runtime
	@$(call func_echo_status, "$@ -> [ Start ]")
	$(ENV_NGINX) -s reload
	@$(call func_echo_success_status, "$@ -> [ Done ]")


### install : Install the apisix (only for luarocks)
.PHONY: install
install: runtime
	$(INSTALL) -d /usr/local/apisix/
	$(INSTALL) -d /usr/local/apisix/logs/
	$(INSTALL) -d /usr/local/apisix/conf/cert
	$(INSTALL) conf/mime.types /usr/local/apisix/conf/mime.types
	$(INSTALL) conf/config.yaml /usr/local/apisix/conf/config.yaml
	$(INSTALL) conf/config-default.yaml /usr/local/apisix/conf/config-default.yaml
	$(INSTALL) conf/debug.yaml /usr/local/apisix/conf/debug.yaml
	$(INSTALL) conf/cert/* /usr/local/apisix/conf/cert/

	$(INSTALL) -d $(INST_LUADIR)/apisix
	$(INSTALL) apisix/*.lua $(INST_LUADIR)/apisix/

	$(INSTALL) -d $(INST_LUADIR)/apisix/admin
	$(INSTALL) apisix/admin/*.lua $(INST_LUADIR)/apisix/admin/

	$(INSTALL) -d $(INST_LUADIR)/apisix/balancer
	$(INSTALL) apisix/balancer/*.lua $(INST_LUADIR)/apisix/balancer/

	$(INSTALL) -d $(INST_LUADIR)/apisix/control
	$(INSTALL) apisix/control/*.lua $(INST_LUADIR)/apisix/control/

	$(INSTALL) -d $(INST_LUADIR)/apisix/core
	$(INSTALL) apisix/core/*.lua $(INST_LUADIR)/apisix/core/

	$(INSTALL) -d $(INST_LUADIR)/apisix/core/dns
	$(INSTALL) apisix/core/dns/*.lua $(INST_LUADIR)/apisix/core/dns

	$(INSTALL) -d $(INST_LUADIR)/apisix/cli
	$(INSTALL) apisix/cli/*.lua $(INST_LUADIR)/apisix/cli/

	$(INSTALL) -d $(INST_LUADIR)/apisix/discovery
	$(INSTALL) apisix/discovery/*.lua $(INST_LUADIR)/apisix/discovery/

	$(INSTALL) -d $(INST_LUADIR)/apisix/http
	$(INSTALL) apisix/http/*.lua $(INST_LUADIR)/apisix/http/

	$(INSTALL) -d $(INST_LUADIR)/apisix/http/router
	$(INSTALL) apisix/http/router/*.lua $(INST_LUADIR)/apisix/http/router/

	$(INSTALL) -d $(INST_LUADIR)/apisix/plugins
	$(INSTALL) apisix/plugins/*.lua $(INST_LUADIR)/apisix/plugins/

	$(INSTALL) -d $(INST_LUADIR)/apisix/plugins/ext-plugin
	$(INSTALL) apisix/plugins/ext-plugin/*.lua $(INST_LUADIR)/apisix/plugins/ext-plugin/

	$(INSTALL) -d $(INST_LUADIR)/apisix/plugins/grpc-transcode
	$(INSTALL) apisix/plugins/grpc-transcode/*.lua $(INST_LUADIR)/apisix/plugins/grpc-transcode/

	$(INSTALL) -d $(INST_LUADIR)/apisix/plugins/ip-restriction
	$(INSTALL) apisix/plugins/ip-restriction/*.lua $(INST_LUADIR)/apisix/plugins/ip-restriction/

	$(INSTALL) -d $(INST_LUADIR)/apisix/plugins/limit-conn
	$(INSTALL) apisix/plugins/limit-conn/*.lua $(INST_LUADIR)/apisix/plugins/limit-conn/

	$(INSTALL) -d $(INST_LUADIR)/apisix/plugins/limit-count
	$(INSTALL) apisix/plugins/limit-count/*.lua $(INST_LUADIR)/apisix/plugins/limit-count/

	$(INSTALL) -d $(INST_LUADIR)/apisix/plugins/prometheus
	$(INSTALL) apisix/plugins/prometheus/*.lua $(INST_LUADIR)/apisix/plugins/prometheus/

	$(INSTALL) -d $(INST_LUADIR)/apisix/plugins/serverless
	$(INSTALL) apisix/plugins/serverless/*.lua $(INST_LUADIR)/apisix/plugins/serverless/

	$(INSTALL) -d $(INST_LUADIR)/apisix/plugins/zipkin
	$(INSTALL) apisix/plugins/zipkin/*.lua $(INST_LUADIR)/apisix/plugins/zipkin/

	$(INSTALL) -d $(INST_LUADIR)/apisix/ssl/router
	$(INSTALL) apisix/ssl/router/*.lua $(INST_LUADIR)/apisix/ssl/router/

	$(INSTALL) -d $(INST_LUADIR)/apisix/stream/plugins
	$(INSTALL) apisix/stream/plugins/*.lua $(INST_LUADIR)/apisix/stream/plugins/

	$(INSTALL) -d $(INST_LUADIR)/apisix/stream/router
	$(INSTALL) apisix/stream/router/*.lua $(INST_LUADIR)/apisix/stream/router/

	$(INSTALL) -d $(INST_LUADIR)/apisix/utils
	$(INSTALL) apisix/utils/*.lua $(INST_LUADIR)/apisix/utils/

	$(INSTALL) bin/apisix $(INST_BINDIR)/apisix

	$(INSTALL) -d $(INST_LUADIR)/apisix/plugins/slslog
	$(INSTALL) apisix/plugins/slslog/*.lua $(INST_LUADIR)/apisix/plugins/slslog/


### test : Run the test case
.PHONY: test
test:
	@$(call func_echo_status, "$@ -> [ Start ]")
	$(ENV_GIT) submodule update --init --recursive
	prove -I../test-nginx/lib -I./ -r -s t/
	@$(call func_echo_success_status, "$@ -> [ Done ]")


### license-check : Check project source code for Apache License
.PHONY: license-check
license-check:
	@$(call func_echo_status, "$@ -> [ Start ]")
	$(ENV_DOCKER) run -it --rm -v $(CURDIR):/github/workspace apache/skywalking-eyes header check
	@$(call func_echo_success_status, "$@ -> [ Done ]")


.PHONY: release-src
release-src: compress-tar
	gpg --batch --yes --armor --detach-sig $(project_release_name).tgz
	shasum -a 512 $(project_release_name).tgz > $(project_release_name).tgz.sha512

	mkdir -p release
	mv $(project_release_name).tgz release/$(project_release_name).tgz
	mv $(project_release_name).tgz.asc release/$(project_release_name).tgz.asc
	mv $(project_release_name).tgz.sha512 release/$(project_release_name).tgz.sha512


.PHONY: compress-tar
compress-tar:
	$(ENV_TAR) -zcvf $(project_release_name).tgz \
	./apisix \
	./bin \
	./conf \
	./rockspec/apisix-$(project_version)-*.rockspec \
	./rockspec/apisix-master-0.rockspec \
	LICENSE \
	Makefile \
	NOTICE \
	*.md


### container
### ci-env-up : launch ci env
.PHONY: ci-env-up
ci-env-up:
	@$(call func_echo_status, "$@ -> [ Start ]")
	$(ENV_DOCKER_COMPOSE) up -d
	@$(call func_echo_success_status, "$@ -> [ Done ]")


### ci-env-ps : ci env ps
.PHONY: ci-env-ps
ci-env-ps:
	@$(call func_echo_status, "$@ -> [ Start ]")
	$(ENV_DOCKER_COMPOSE) ps
	@$(call func_echo_success_status, "$@ -> [ Done ]")


### ci-env-rebuild : ci env image rebuild
.PHONY: ci-env-rebuild
ci-env-rebuild:
	@$(call func_echo_status, "$@ -> [ Start ]")
	$(ENV_DOCKER_COMPOSE) build
	@$(call func_echo_success_status, "$@ -> [ Done ]")


### ci-env-down : destroy ci env
.PHONY: ci-env-down
ci-env-down:
	@$(call func_echo_status, "$@ -> [ Start ]")
	$(ENV_DOCKER_COMPOSE) down
	@$(call func_echo_success_status, "$@ -> [ Done ]")
