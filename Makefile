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

INST_PREFIX ?= /usr
INST_LIBDIR ?= $(INST_PREFIX)/lib64/lua/5.1
INST_LUADIR ?= $(INST_PREFIX)/share/lua/5.1
INST_BINDIR ?= /usr/bin
INSTALL ?= install
UNAME ?= $(shell uname)
OR_EXEC ?= $(shell which openresty)
LUAROCKS_VER ?= $(shell luarocks --version | grep -E -o  "luarocks [0-9]+.")


.PHONY: default
default:
ifeq ($(OR_EXEC), )
ifeq ("$(wildcard /usr/local/openresty-debug/bin/openresty)", "")
	@echo "ERROR: OpenResty not found. You have to install OpenResty and add the binary file to PATH before install Apache APISIX."
	exit 1
endif
endif

LUAJIT_DIR ?= $(shell ${OR_EXEC} -V 2>&1 | grep prefix | grep -Eo 'prefix=(.*)/nginx\s+--' | grep -Eo '/.*/')luajit

### help:             Show Makefile rules.
.PHONY: help
help: default
	@echo Makefile rules:
	@echo
	@grep -E '^### [-A-Za-z0-9_]+:' Makefile | sed 's/###/   /'


### deps:             Installation dependencies
.PHONY: deps
deps: default
ifeq ($(LUAROCKS_VER),luarocks 3.)
	luarocks install --lua-dir=$(LUAJIT_DIR) rockspec/apisix-master-0.rockspec --tree=deps --only-deps --local
else
	luarocks install rockspec/apisix-master-0.rockspec --tree=deps --only-deps --local
endif


### utils:            Installation tools
.PHONY: utils
utils:
ifeq ("$(wildcard utils/lj-releng)", "")
	wget -O utils/lj-releng https://raw.githubusercontent.com/iresty/openresty-devel-utils/master/lj-releng
	chmod a+x utils/lj-releng
endif


### lint:             Lint Lua source code
.PHONY: lint
lint: utils
	./utils/check-lua-code-style.sh


### init:             Initialize the runtime environment
.PHONY: init
init: default
	./bin/apisix init
	./bin/apisix init_etcd


### run:              Start the apisix server
.PHONY: run
run: default
ifeq ("$(wildcard logs/nginx.pid)", "")
	mkdir -p logs
	mkdir -p /tmp/apisix_cores/
	$(OR_EXEC) -p $$PWD/ -c $$PWD/conf/nginx.conf
else
	@echo "APISIX is running..."
endif


### stop:             Stop the apisix server
.PHONY: stop
stop: default
	$(OR_EXEC) -p $$PWD/ -c $$PWD/conf/nginx.conf -s stop


### verify:           Verify the configuration of apisix server
.PHONY: verify
verify: default
	$(OR_EXEC) -p $$PWD/ -c $$PWD/conf/nginx.conf -t


### clean:            Remove generated files
.PHONY: clean
clean:
	rm -rf logs/


### reload:           Reload the apisix server
.PHONY: reload
reload: default
	$(OR_EXEC) -p $$PWD/  -c $$PWD/conf/nginx.conf -s reload


### install:          Install the apisix
.PHONY: install
install: default
	$(INSTALL) -d /usr/local/apisix/
	$(INSTALL) -d /usr/local/apisix/logs/
	$(INSTALL) -d /usr/local/apisix/conf/cert
	$(INSTALL) conf/mime.types /usr/local/apisix/conf/mime.types
	$(INSTALL) conf/config.yaml /usr/local/apisix/conf/config.yaml
	$(INSTALL) conf/cert/apisix.* /usr/local/apisix/conf/cert/

	$(INSTALL) -d $(INST_LUADIR)/apisix
	$(INSTALL) apisix/*.lua $(INST_LUADIR)/apisix/

	$(INSTALL) -d $(INST_LUADIR)/apisix/admin
	$(INSTALL) apisix/admin/*.lua $(INST_LUADIR)/apisix/admin/

	$(INSTALL) -d $(INST_LUADIR)/apisix/balancer
	$(INSTALL) apisix/balancer/*.lua $(INST_LUADIR)/apisix/balancer/

	$(INSTALL) -d $(INST_LUADIR)/apisix/core
	$(INSTALL) apisix/core/*.lua $(INST_LUADIR)/apisix/core/

	$(INSTALL) -d $(INST_LUADIR)/apisix/http
	$(INSTALL) apisix/http/*.lua $(INST_LUADIR)/apisix/http/

	$(INSTALL) -d $(INST_LUADIR)/apisix/http/router
	$(INSTALL) apisix/http/router/*.lua $(INST_LUADIR)/apisix/http/router/

	$(INSTALL) -d $(INST_LUADIR)/apisix/discovery
	$(INSTALL) apisix/discovery/*.lua $(INST_LUADIR)/apisix/discovery/

	$(INSTALL) -d $(INST_LUADIR)/apisix/plugins
	$(INSTALL) apisix/plugins/*.lua $(INST_LUADIR)/apisix/plugins/

	$(INSTALL) -d $(INST_LUADIR)/apisix/plugins/grpc-transcode
	$(INSTALL) apisix/plugins/grpc-transcode/*.lua $(INST_LUADIR)/apisix/plugins/grpc-transcode/

	$(INSTALL) -d $(INST_LUADIR)/apisix/plugins/limit-count
	$(INSTALL) apisix/plugins/limit-count/*.lua $(INST_LUADIR)/apisix/plugins/limit-count/

	$(INSTALL) -d $(INST_LUADIR)/apisix/plugins/prometheus
	$(INSTALL) apisix/plugins/prometheus/*.lua $(INST_LUADIR)/apisix/plugins/prometheus/

	$(INSTALL) -d $(INST_LUADIR)/apisix/plugins/zipkin
	$(INSTALL) apisix/plugins/zipkin/*.lua $(INST_LUADIR)/apisix/plugins/zipkin/

	$(INSTALL) -d $(INST_LUADIR)/apisix/plugins/skywalking
	$(INSTALL) apisix/plugins/skywalking/*.lua $(INST_LUADIR)/apisix/plugins/skywalking/

	$(INSTALL) -d $(INST_LUADIR)/apisix/stream/plugins
	$(INSTALL) apisix/stream/plugins/*.lua $(INST_LUADIR)/apisix/stream/plugins/

	$(INSTALL) -d $(INST_LUADIR)/apisix/stream/router
	$(INSTALL) apisix/stream/router/*.lua $(INST_LUADIR)/apisix/stream/router/

	$(INSTALL) -d $(INST_LUADIR)/apisix/utils
	$(INSTALL) apisix/utils/*.lua $(INST_LUADIR)/apisix/utils/

	$(INSTALL) README.md $(INST_CONFDIR)/README.md
	$(INSTALL) bin/apisix $(INST_BINDIR)/apisix


### test:             Run the test case
test:
	prove -I../test-nginx/lib -I./ -r -s t/

### license-check:    Check Lua source code for Apache License
.PHONY: license-check
license-check:
ifeq ("$(wildcard .travis/openwhisk-utilities/scancode/scanCode.py)", "")
	git clone https://github.com/apache/openwhisk-utilities.git .travis/openwhisk-utilities
	cp .travis/ASF* .travis/openwhisk-utilities/scancode/
endif
	.travis/openwhisk-utilities/scancode/scanCode.py --config .travis/ASF-Release.cfg ./

