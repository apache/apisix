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
VERSION                ?= master
project_name           ?= apache-apisix
project_release_name   ?= $(project_name)-$(VERSION)-src


# Hyperconverged Infrastructure
ENV_OS_NAME            ?= $(shell uname -s | tr '[:upper:]' '[:lower:]')
ENV_OS_ARCH            ?= $(shell uname -m | tr '[:upper:]' '[:lower:]')
ENV_APISIX             ?= $(CURDIR)/bin/apisix
ENV_GIT                ?= git
ENV_TAR                ?= tar
ENV_INSTALL            ?= install
ENV_RM                 ?= rm -vf
ENV_DOCKER             ?= docker
ENV_DOCKER_COMPOSE     ?= docker-compose --project-directory $(CURDIR) -p $(project_name) -f $(project_compose_ci)
ENV_NGINX              ?= $(ENV_NGINX_EXEC) -p $(CURDIR) -c $(CURDIR)/conf/nginx.conf
ENV_NGINX_EXEC         := $(shell command -v openresty 2>/dev/null || command -v nginx 2>/dev/null)
ENV_OPENSSL_PREFIX     ?= $(addprefix $(ENV_NGINX_PREFIX), openssl)
ENV_LUAROCKS           ?= luarocks
## These variables can be injected by luarocks
ENV_INST_PREFIX        ?= /usr
ENV_INST_LUADIR        ?= $(ENV_INST_PREFIX)/share/lua/5.1
ENV_INST_BINDIR        ?= $(ENV_INST_PREFIX)/bin
ENV_HOMEBREW_PREFIX    ?= /usr/local

ifneq ($(shell whoami), root)
	ENV_LUAROCKS_FLAG_LOCAL := --local
endif

ifdef ENV_LUAROCKS_SERVER
	ENV_LUAROCKS_SERVER_OPT := --server $(ENV_LUAROCKS_SERVER)
endif

# Execute only in the presence of ENV_NGINX_EXEC to avoid unexpected error output
ifneq ($(ENV_NGINX_EXEC), )
	ENV_NGINX_PREFIX := $(shell $(ENV_NGINX_EXEC) -V 2>&1 | grep -Eo 'prefix=(.*)/nginx\s+' | grep -Eo '/.*/')
	# OpenResty 1.17.8 or higher version uses openssl111 as the openssl dirname.
	ifeq ($(shell test -d $(addprefix $(ENV_NGINX_PREFIX), openssl111) && echo -n yes), yes)
		ENV_OPENSSL_PREFIX := $(addprefix $(ENV_NGINX_PREFIX), openssl111)
	endif
endif

# ENV patch for darwin
ifeq ($(ENV_OS_NAME), darwin)
	ifeq ($(ENV_OS_ARCH), arm64)
		ENV_HOMEBREW_PREFIX := /opt/homebrew
	endif

	# OSX archive `._` cache file
	ENV_TAR      := COPYFILE_DISABLE=1 $(ENV_TAR)
	ENV_LUAROCKS := $(ENV_LUAROCKS) --lua-dir=$(ENV_HOMEBREW_PREFIX)/opt/lua@5.1

	ifeq ($(shell test -d $(ENV_HOMEBREW_PREFIX)/opt/openresty-openssl && echo -n yes), yes)
		ENV_OPENSSL_PREFIX := $(ENV_HOMEBREW_PREFIX)/opt/openresty-openssl
	endif
	ifeq ($(shell test -d $(ENV_HOMEBREW_PREFIX)/opt/openresty-openssl111 && echo -n yes), yes)
		ENV_OPENSSL_PREFIX := $(ENV_HOMEBREW_PREFIX)/opt/openresty-openssl111
	endif
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
ifeq ($(ENV_NGINX_EXEC), )
ifeq ("$(wildcard /usr/local/openresty-debug/bin/openresty)", "")
	@$(call func_echo_warn_status, "WARNING: OpenResty not found. You have to install OpenResty and add the binary file to PATH before install Apache APISIX.")
	exit 1
else
	$(eval ENV_NGINX_EXEC := /usr/local/openresty-debug/bin/openresty)
	@$(call func_echo_status, "Use openresty-debug as default runtime")
endif
endif


### help : Show Makefile rules
### 	If there're awk failures, please make sure
### 	you are using awk or gawk
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
	$(eval ENV_LUAROCKS_VER := $(shell $(ENV_LUAROCKS) --version | grep -E -o "luarocks [0-9]+."))
	@if [ '$(ENV_LUAROCKS_VER)' = 'luarocks 3.' ]; then \
		mkdir -p ~/.luarocks; \
		$(ENV_LUAROCKS) config $(ENV_LUAROCKS_FLAG_LOCAL) variables.OPENSSL_LIBDIR $(addprefix $(ENV_OPENSSL_PREFIX), /lib); \
		$(ENV_LUAROCKS) config $(ENV_LUAROCKS_FLAG_LOCAL) variables.OPENSSL_INCDIR $(addprefix $(ENV_OPENSSL_PREFIX), /include); \
		$(ENV_LUAROCKS) install rockspec/apisix-master-0.rockspec --tree=deps --only-deps --local $(ENV_LUAROCKS_SERVER_OPT); \
	else \
		$(call func_echo_warn_status, "WARNING: You're not using LuaRocks 3.x; please remove the luarocks and reinstall it via https://raw.githubusercontent.com/apache/apisix/master/utils/linux-install-luarocks.sh"); \
		exit 1; \
	fi


### undeps : Uninstallation dependencies
.PHONY: undeps
undeps:
	@$(call func_echo_status, "$@ -> [ Start ]")
	$(ENV_LUAROCKS) purge --tree=deps
	@$(call func_echo_success_status, "$@ -> [ Done ]")


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
	$(ENV_APISIX) reload
	@$(call func_echo_success_status, "$@ -> [ Done ]")


### install : Install the apisix (only for luarocks)
.PHONY: install
install: runtime
	$(ENV_INSTALL) -d /usr/local/apisix/
	$(ENV_INSTALL) -d /usr/local/apisix/logs/
	$(ENV_INSTALL) -d /usr/local/apisix/conf/cert
	$(ENV_INSTALL) conf/mime.types /usr/local/apisix/conf/mime.types
	$(ENV_INSTALL) conf/config.yaml /usr/local/apisix/conf/config.yaml
	$(ENV_INSTALL) conf/config-default.yaml /usr/local/apisix/conf/config-default.yaml
	$(ENV_INSTALL) conf/debug.yaml /usr/local/apisix/conf/debug.yaml
	$(ENV_INSTALL) conf/cert/* /usr/local/apisix/conf/cert/

	# Lua directories listed in alphabetical order
	$(ENV_INSTALL) -d $(ENV_INST_LUADIR)/apisix
	$(ENV_INSTALL) apisix/*.lua $(ENV_INST_LUADIR)/apisix/

	$(ENV_INSTALL) -d $(ENV_INST_LUADIR)/apisix/include/apisix/model
	$(ENV_INSTALL) apisix/include/apisix/model/*.proto $(ENV_INST_LUADIR)/apisix/include/apisix/model/

	$(ENV_INSTALL) -d $(ENV_INST_LUADIR)/apisix/admin
	$(ENV_INSTALL) apisix/admin/*.lua $(ENV_INST_LUADIR)/apisix/admin/

	$(ENV_INSTALL) -d $(ENV_INST_LUADIR)/apisix/balancer
	$(ENV_INSTALL) apisix/balancer/*.lua $(ENV_INST_LUADIR)/apisix/balancer/

	$(ENV_INSTALL) -d $(ENV_INST_LUADIR)/apisix/control
	$(ENV_INSTALL) apisix/control/*.lua $(ENV_INST_LUADIR)/apisix/control/

	$(ENV_INSTALL) -d $(ENV_INST_LUADIR)/apisix/core
	$(ENV_INSTALL) apisix/core/*.lua $(ENV_INST_LUADIR)/apisix/core/

	$(ENV_INSTALL) -d $(ENV_INST_LUADIR)/apisix/core/dns
	$(ENV_INSTALL) apisix/core/dns/*.lua $(ENV_INST_LUADIR)/apisix/core/dns

	$(ENV_INSTALL) -d $(ENV_INST_LUADIR)/apisix/cli
	$(ENV_INSTALL) apisix/cli/*.lua $(ENV_INST_LUADIR)/apisix/cli/

	$(ENV_INSTALL) -d $(ENV_INST_LUADIR)/apisix/discovery
	$(ENV_INSTALL) apisix/discovery/*.lua $(ENV_INST_LUADIR)/apisix/discovery/
	$(ENV_INSTALL) -d $(ENV_INST_LUADIR)/apisix/discovery/{consul_kv,dns,eureka,nacos,kubernetes,tars}
	$(ENV_INSTALL) apisix/discovery/consul_kv/*.lua $(ENV_INST_LUADIR)/apisix/discovery/consul_kv
	$(ENV_INSTALL) apisix/discovery/dns/*.lua $(ENV_INST_LUADIR)/apisix/discovery/dns
	$(ENV_INSTALL) apisix/discovery/eureka/*.lua $(ENV_INST_LUADIR)/apisix/discovery/eureka
	$(ENV_INSTALL) apisix/discovery/nacos/*.lua $(ENV_INST_LUADIR)/apisix/discovery/nacos
	$(ENV_INSTALL) apisix/discovery/kubernetes/*.lua $(ENV_INST_LUADIR)/apisix/discovery/kubernetes
	$(ENV_INSTALL) apisix/discovery/tars/*.lua $(ENV_INST_LUADIR)/apisix/discovery/tars

	$(ENV_INSTALL) -d $(ENV_INST_LUADIR)/apisix/pubsub
	$(ENV_INSTALL) apisix/pubsub/*.lua $(ENV_INST_LUADIR)/apisix/pubsub/

	$(ENV_INSTALL) -d $(ENV_INST_LUADIR)/apisix/http
	$(ENV_INSTALL) apisix/http/*.lua $(ENV_INST_LUADIR)/apisix/http/

	$(ENV_INSTALL) -d $(ENV_INST_LUADIR)/apisix/http/router
	$(ENV_INSTALL) apisix/http/router/*.lua $(ENV_INST_LUADIR)/apisix/http/router/

	$(ENV_INSTALL) -d $(ENV_INST_LUADIR)/apisix/plugins
	$(ENV_INSTALL) apisix/plugins/*.lua $(ENV_INST_LUADIR)/apisix/plugins/

	$(ENV_INSTALL) -d $(ENV_INST_LUADIR)/apisix/plugins/ext-plugin
	$(ENV_INSTALL) apisix/plugins/ext-plugin/*.lua $(ENV_INST_LUADIR)/apisix/plugins/ext-plugin/

	$(ENV_INSTALL) -d $(ENV_INST_LUADIR)/apisix/plugins/grpc-transcode
	$(ENV_INSTALL) apisix/plugins/grpc-transcode/*.lua $(ENV_INST_LUADIR)/apisix/plugins/grpc-transcode/

	$(ENV_INSTALL) -d $(ENV_INST_LUADIR)/apisix/plugins/ip-restriction
	$(ENV_INSTALL) apisix/plugins/ip-restriction/*.lua $(ENV_INST_LUADIR)/apisix/plugins/ip-restriction/

	$(ENV_INSTALL) -d $(ENV_INST_LUADIR)/apisix/plugins/limit-conn
	$(ENV_INSTALL) apisix/plugins/limit-conn/*.lua $(ENV_INST_LUADIR)/apisix/plugins/limit-conn/

	$(ENV_INSTALL) -d $(ENV_INST_LUADIR)/apisix/plugins/limit-count
	$(ENV_INSTALL) apisix/plugins/limit-count/*.lua $(ENV_INST_LUADIR)/apisix/plugins/limit-count/

	$(ENV_INSTALL) -d $(ENV_INST_LUADIR)/apisix/plugins/google-cloud-logging
	$(ENV_INSTALL) apisix/plugins/google-cloud-logging/*.lua $(ENV_INST_LUADIR)/apisix/plugins/google-cloud-logging/

	$(ENV_INSTALL) -d $(ENV_INST_LUADIR)/apisix/plugins/opa
	$(ENV_INSTALL) apisix/plugins/opa/*.lua $(ENV_INST_LUADIR)/apisix/plugins/opa/

	$(ENV_INSTALL) -d $(ENV_INST_LUADIR)/apisix/plugins/prometheus
	$(ENV_INSTALL) apisix/plugins/prometheus/*.lua $(ENV_INST_LUADIR)/apisix/plugins/prometheus/

	$(ENV_INSTALL) -d $(ENV_INST_LUADIR)/apisix/plugins/proxy-cache
	$(ENV_INSTALL) apisix/plugins/proxy-cache/*.lua $(ENV_INST_LUADIR)/apisix/plugins/proxy-cache/

	$(ENV_INSTALL) -d $(ENV_INST_LUADIR)/apisix/plugins/serverless
	$(ENV_INSTALL) apisix/plugins/serverless/*.lua $(ENV_INST_LUADIR)/apisix/plugins/serverless/

	$(ENV_INSTALL) -d $(ENV_INST_LUADIR)/apisix/plugins/slslog
	$(ENV_INSTALL) apisix/plugins/slslog/*.lua $(ENV_INST_LUADIR)/apisix/plugins/slslog/

	$(ENV_INSTALL) -d $(ENV_INST_LUADIR)/apisix/plugins/syslog
	$(ENV_INSTALL) apisix/plugins/syslog/*.lua $(ENV_INST_LUADIR)/apisix/plugins/syslog/

	$(ENV_INSTALL) -d $(ENV_INST_LUADIR)/apisix/plugins/zipkin
	$(ENV_INSTALL) apisix/plugins/zipkin/*.lua $(ENV_INST_LUADIR)/apisix/plugins/zipkin/

	$(ENV_INSTALL) -d $(ENV_INST_LUADIR)/apisix/ssl/router
	$(ENV_INSTALL) apisix/ssl/router/*.lua $(ENV_INST_LUADIR)/apisix/ssl/router/

	$(ENV_INSTALL) -d $(ENV_INST_LUADIR)/apisix/stream
	$(ENV_INSTALL) apisix/stream/*.lua $(ENV_INST_LUADIR)/apisix/stream/

	$(ENV_INSTALL) -d $(ENV_INST_LUADIR)/apisix/stream/plugins
	$(ENV_INSTALL) apisix/stream/plugins/*.lua $(ENV_INST_LUADIR)/apisix/stream/plugins/

	$(ENV_INSTALL) -d $(ENV_INST_LUADIR)/apisix/stream/router
	$(ENV_INSTALL) apisix/stream/router/*.lua $(ENV_INST_LUADIR)/apisix/stream/router/

	$(ENV_INSTALL) -d $(ENV_INST_LUADIR)/apisix/stream/xrpc
	$(ENV_INSTALL) apisix/stream/xrpc/*.lua $(ENV_INST_LUADIR)/apisix/stream/xrpc/

	$(ENV_INSTALL) -d $(ENV_INST_LUADIR)/apisix/stream/xrpc/protocols/redis
	$(ENV_INSTALL) apisix/stream/xrpc/protocols/redis/*.lua $(ENV_INST_LUADIR)/apisix/stream/xrpc/protocols/redis/

	$(ENV_INSTALL) -d $(ENV_INST_LUADIR)/apisix/utils
	$(ENV_INSTALL) apisix/utils/*.lua $(ENV_INST_LUADIR)/apisix/utils/

	$(ENV_INSTALL) bin/apisix $(ENV_INST_BINDIR)/apisix


### uninstall : Uninstall the apisix
.PHONY: uninstall
uninstall:
	@$(call func_echo_status, "$@ -> [ Start ]")
	$(ENV_RM) -r /usr/local/apisix
	$(ENV_RM) -r $(ENV_INST_LUADIR)/apisix
	$(ENV_RM) $(ENV_INST_BINDIR)/apisix
	@$(call func_echo_success_status, "$@ -> [ Done ]")


### test : Run the test case
.PHONY: test
test: runtime
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
	@$(call func_echo_status, "$@ -> [ Start ]")
	gpg --batch --yes --armor --detach-sig $(project_release_name).tgz
	shasum -a 512 $(project_release_name).tgz > $(project_release_name).tgz.sha512

	$(call func_check_folder,release)
	mv $(project_release_name).tgz release/$(project_release_name).tgz
	mv $(project_release_name).tgz.asc release/$(project_release_name).tgz.asc
	mv $(project_release_name).tgz.sha512 release/$(project_release_name).tgz.sha512
	./utils/gen-vote-contents.sh $(VERSION)
	@$(call func_echo_success_status, "$@ -> [ Done ]")


.PHONY: compress-tar
compress-tar:
	# The $VERSION can be major.minor.patch (from developer)
	# or major.minor (from the branch name in the CI)
	$(ENV_TAR) -zcvf $(project_release_name).tgz \
	./apisix \
	./bin \
	./conf \
	./rockspec/apisix-$(VERSION)*.rockspec \
	./rockspec/apisix-master-0.rockspec \
	LICENSE \
	Makefile \
	NOTICE \
	*.md


### container
### ci-env-up : CI env launch
.PHONY: ci-env-up
ci-env-up:
	@$(call func_echo_status, "$@ -> [ Start ]")
	$(ENV_DOCKER_COMPOSE) up -d
	@$(call func_echo_success_status, "$@ -> [ Done ]")


### ci-env-ps : CI env ps
.PHONY: ci-env-ps
ci-env-ps:
	@$(call func_echo_status, "$@ -> [ Start ]")
	$(ENV_DOCKER_COMPOSE) ps
	@$(call func_echo_success_status, "$@ -> [ Done ]")


### ci-env-rebuild : CI env image rebuild
.PHONY: ci-env-rebuild
ci-env-rebuild:
	@$(call func_echo_status, "$@ -> [ Start ]")
	$(ENV_DOCKER_COMPOSE) build
	@$(call func_echo_success_status, "$@ -> [ Done ]")


### ci-env-down : CI env destroy
.PHONY: ci-env-down
ci-env-down:
	@$(call func_echo_status, "$@ -> [ Start ]")
	$(ENV_DOCKER_COMPOSE) down
	@$(call func_echo_success_status, "$@ -> [ Done ]")
