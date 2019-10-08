INST_PREFIX ?= /usr
INST_LIBDIR ?= $(INST_PREFIX)/lib64/lua/5.1
INST_LUADIR ?= $(INST_PREFIX)/share/lua/5.1
INST_BINDIR ?= /usr/bin
INSTALL ?= install
UNAME ?= $(shell uname)
OR_EXEC ?= $(shell which openresty)
LUA_JIT_DIR ?= $(shell ${OR_EXEC} -V 2>&1 | grep prefix | grep -Eo 'prefix=(.*?)/nginx' | grep -Eo '/.*/')luajit
LUAROCKS_VER ?= $(shell luarocks --version | grep -E -o  "luarocks [0-9]+.")
lj-releng-exist = $(shell if [ -f 'utils/lj-releng' ]; then echo "exist"; else echo "not_exist"; fi;)


.PHONY: default
default:


### help:         Show Makefile rules.
.PHONY: help
help:
	@echo Makefile rules:
	@echo
	@grep -E '^### [-A-Za-z0-9_]+:' Makefile | sed 's/###/   /'


### dev:          Create a development ENV
.PHONY: dev
dev:
ifeq ($(UNAME),Darwin)
	luarocks install --lua-dir=$(LUA_JIT_DIR) rockspec/apisix-dev-1.0-0.rockspec --tree=deps --only-deps --local
else ifneq ($(LUAROCKS_VER),'luarocks 3.')
	luarocks install rockspec/apisix-dev-1.0-0.rockspec --tree=deps --only-deps --local
else
	luarocks install --lua-dir=/usr/local/openresty/luajit rockspec/apisix-dev-1.0-0.rockspec --tree=deps --only-deps --local
endif
ifeq ($(lj-releng-exist), not_exist)
	wget -O utils/lj-releng https://raw.githubusercontent.com/iresty/openresty-devel-utils/iresty/lj-releng
	chmod a+x utils/lj-releng
endif

### dev_r3:       Create a development ENV for r3
.PHONY: dev_r3
dev_r3:
ifeq ($(UNAME),Darwin)
	luarocks install --lua-dir=$(LUA_JIT_DIR) lua-resty-libr3 --tree=deps --local
else ifneq ($(LUAROCKS_VER),'luarocks 3.')
	luarocks install lua-resty-libr3 --tree=deps --local
else
	luarocks install --lua-dir=/usr/local/openresty/luajit lua-resty-libr3 --tree=deps --local
endif


### check:        Check Lua source code
.PHONY: check
check:
	luacheck -q lua
	./utils/lj-releng lua/*.lua lua/apisix/*.lua \
		lua/apisix/admin/*.lua \
		lua/apisix/core/*.lua \
		lua/apisix/http/*.lua \
		lua/apisix/plugins/*.lua \
		lua/apisix/plugins/grpc-transcode/*.lua \
		lua/apisix/plugins/limit-count/*.lua > \
		/tmp/check.log 2>&1 || (cat /tmp/check.log && exit 1)


### init:         Initialize the runtime environment
.PHONY: init
init:
	./bin/apisix init
	./bin/apisix init_etcd


### run:          Start the apisix server
.PHONY: run
run:
	mkdir -p logs
	mkdir -p /tmp/apisix_cores/
	$(OR_EXEC) -p $$PWD/ -c $$PWD/conf/nginx.conf


### stop:         Stop the apisix server
.PHONY: stop
stop:
	$(OR_EXEC) -p $$PWD/ -c $$PWD/conf/nginx.conf -s stop


### clean:        Remove generated files
.PHONY: clean
clean:
	rm -rf logs/


### reload:       Reload the apisix server
.PHONY: reload
reload:
	$(OR_EXEC) -p $$PWD/  -c $$PWD/conf/nginx.conf -s reload


### install:      Install the apisix
.PHONY: install
install:
	$(INSTALL) -d /usr/local/apisix/dashboard
	cd `mktemp -d /tmp/apisix.XXXXXX` && \
		git clone https://github.com/iresty/apisix.git && \
		cd apisix && \
		git submodule update --init --recursive && \
		cp -r dashboard/* /usr/local/apisix/dashboard
	chmod -R 755 /usr/local/apisix/dashboard

	$(INSTALL) -d /usr/local/apisix/logs/
	$(INSTALL) -d /usr/local/apisix/conf/cert
	$(INSTALL) conf/mime.types /usr/local/apisix/conf/mime.types
	$(INSTALL) conf/config.yaml /usr/local/apisix/conf/config.yaml
	$(INSTALL) conf/cert/apisix.* /usr/local/apisix/conf/cert/

	$(INSTALL) -d $(INST_LUADIR)/apisix/lua
	$(INSTALL) lua/*.lua $(INST_LUADIR)/apisix/lua/

	$(INSTALL) -d $(INST_LUADIR)/apisix/lua/apisix
	$(INSTALL) lua/apisix/*.lua $(INST_LUADIR)/apisix/lua/apisix/

	$(INSTALL) -d $(INST_LUADIR)/apisix/lua/apisix/admin
	$(INSTALL) lua/apisix/admin/*.lua $(INST_LUADIR)/apisix/lua/apisix/admin/

	$(INSTALL) -d $(INST_LUADIR)/apisix/lua/apisix/core
	$(INSTALL) lua/apisix/core/*.lua $(INST_LUADIR)/apisix/lua/apisix/core/

	$(INSTALL) -d $(INST_LUADIR)/apisix/lua/apisix/http
	$(INSTALL) lua/apisix/http/*.lua $(INST_LUADIR)/apisix/lua/apisix/http/

	$(INSTALL) -d $(INST_LUADIR)/apisix/lua/apisix/http/router
	$(INSTALL) lua/apisix/http/router/*.lua $(INST_LUADIR)/apisix/lua/apisix/http/router/

	$(INSTALL) -d $(INST_LUADIR)/apisix/lua/apisix/plugins
	$(INSTALL) lua/apisix/plugins/*.lua $(INST_LUADIR)/apisix/lua/apisix/plugins/

	$(INSTALL) -d $(INST_LUADIR)/apisix/lua/apisix/plugins/grpc-transcode
	$(INSTALL) lua/apisix/plugins/grpc-transcode/*.lua $(INST_LUADIR)/apisix/lua/apisix/plugins/grpc-transcode/

	$(INSTALL) -d $(INST_LUADIR)/apisix/lua/apisix/plugins/limit-count
	$(INSTALL) lua/apisix/plugins/limit-count/*.lua $(INST_LUADIR)/apisix/lua/apisix/plugins/limit-count/

	$(INSTALL) -d $(INST_LUADIR)/apisix/lua/apisix/plugins/prometheus
	$(INSTALL) lua/apisix/plugins/prometheus/*.lua $(INST_LUADIR)/apisix/lua/apisix/plugins/prometheus/

	$(INSTALL) -d $(INST_LUADIR)/apisix/lua/apisix/plugins/zipkin
	$(INSTALL) lua/apisix/plugins/zipkin/*.lua $(INST_LUADIR)/apisix/lua/apisix/plugins/zipkin/

	$(INSTALL) -d $(INST_LUADIR)/apisix/lua/apisix/stream
	$(INSTALL) lua/apisix/stream/*.lua $(INST_LUADIR)/apisix/lua/apisix/stream/

	$(INSTALL) -d $(INST_LUADIR)/apisix/lua/apisix/stream/plugins
	$(INSTALL) lua/apisix/stream/plugins/*.lua $(INST_LUADIR)/apisix/lua/apisix/stream/plugins/

	$(INSTALL) -d $(INST_LUADIR)/apisix/lua/apisix/stream/router
	$(INSTALL) lua/apisix/stream/router/*.lua $(INST_LUADIR)/apisix/lua/apisix/stream/router/

	$(INSTALL) COPYRIGHT $(INST_CONFDIR)/COPYRIGHT
	$(INSTALL) README.md $(INST_CONFDIR)/README.md
	$(INSTALL) bin/apisix $(INST_BINDIR)/apisix


### test:         Run the test case
test:
ifeq ($(UNAME),Darwin)
	prove -I../test-nginx/lib -I./ -r -s t/
else
	prove -I../test-nginx/lib -r -s t/
endif
