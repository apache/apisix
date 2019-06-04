INST_PREFIX ?= /usr
INST_LIBDIR ?= $(INST_PREFIX)/lib64/lua/5.1
INST_LUADIR ?= $(INST_PREFIX)/share/lua/5.1
INST_BINDIR ?= /usr/bin
INSTALL ?= install

### help:         Show Makefile rules.
.PHONY: help
help:
	@echo Makefile rules:
	@echo
	@grep -E '^### [-A-Za-z0-9_]+:' Makefile | sed 's/###/   /'


### run:          Start the apisix server
.PHONY: run
run:
	mkdir -p logs
	sudo $$(which openresty) -p $$PWD/


### stop:         Stop the apisix server
.PHONY: stop
stop:
	sudo $$(which openresty) -p $$PWD/ -s stop


### clean:        Remove generated files
.PHONY: clean
clean:
	rm -rf logs/


### reload:       Reload the apisix server
.PHONY: reload
reload:
	sudo $$(which openresty) -p $$PWD/ -s reload


### install:      Install the apisix
.PHONY: install
install:
	$(INSTALL) -d logs/ /usr/local/apisix/logs/
	$(INSTALL) -D conf/mime.types /usr/local/apisix/conf/mime.types
	$(INSTALL) conf/config.yaml /usr/local/apisix/conf/config.yaml

	$(INSTALL) -D lua/apisix.lua $(INST_LUADIR)/apisix/lua/apisix.lua
	$(INSTALL) -D lua/apisix/core/response.lua $(INST_LUADIR)/apisix/lua/apisix/core/response.lua
	$(INSTALL)    lua/apisix/core/config_etcd.lua $(INST_LUADIR)/apisix/lua/apisix/core/config_etcd.lua
	$(INSTALL)    lua/apisix/core/table.lua $(INST_LUADIR)/apisix/lua/apisix/core/table.lua
	$(INSTALL)    lua/apisix/core/request.lua $(INST_LUADIR)/apisix/lua/apisix/core/request.lua
	$(INSTALL)    lua/apisix/core/config_local.lua $(INST_LUADIR)/apisix/lua/apisix/core/config_local.lua
	$(INSTALL)    lua/apisix/core/schema.lua $(INST_LUADIR)/apisix/lua/apisix/core/schema.lua
	$(INSTALL)    lua/apisix/core/yaml.lua $(INST_LUADIR)/apisix/lua/apisix/core/yaml.lua
	$(INSTALL)    lua/apisix/core/lrucache.lua $(INST_LUADIR)/apisix/lua/apisix/core/lrucache.lua
	$(INSTALL)    lua/apisix/core/ctx.lua $(INST_LUADIR)/apisix/lua/apisix/core/ctx.lua
	$(INSTALL)    lua/apisix/core/typeof.lua $(INST_LUADIR)/apisix/lua/apisix/core/typeof.lua
	$(INSTALL)    lua/apisix/core/log.lua $(INST_LUADIR)/apisix/lua/apisix/core/log.lua
	$(INSTALL)    lua/apisix/route.lua $(INST_LUADIR)/apisix/lua/apisix/route.lua
	$(INSTALL)    lua/apisix/balancer.lua $(INST_LUADIR)/apisix/lua/apisix/balancer.lua
	$(INSTALL)    lua/apisix/plugin.lua $(INST_LUADIR)/apisix/lua/apisix/plugin.lua
	$(INSTALL)    lua/apisix/core.lua $(INST_LUADIR)/apisix/lua/apisix/core.lua
	$(INSTALL)    lua/apisix/service.lua $(INST_LUADIR)/apisix/lua/apisix/service.lua

	$(INSTALL) -D lua/apisix/plugins/prometheus/base_prometheus.lua $(INST_LUADIR)/apisix/lua/apisix/plugins/prometheus/base_prometheus.lua
	$(INSTALL)    lua/apisix/plugins/prometheus/exporter.lua $(INST_LUADIR)/apisix/lua/apisix/plugins/prometheus/exporter.lua
	$(INSTALL)    lua/apisix/plugins/example-plugin.lua $(INST_LUADIR)/apisix/lua/apisix/plugins/example-plugin.lua
	$(INSTALL)    lua/apisix/plugins/prometheus.lua $(INST_LUADIR)/apisix/lua/apisix/plugins/prometheus.lua
	$(INSTALL)    lua/apisix/plugins/limit-count.lua $(INST_LUADIR)/apisix/lua/apisix/plugins/limit-count.lua
	$(INSTALL)    lua/apisix/plugins/limit-req.lua $(INST_LUADIR)/apisix/lua/apisix/plugins/limit-req.lua
	$(INSTALL)    lua/apisix/plugins/key-auth.lua $(INST_LUADIR)/apisix/lua/apisix/plugins/key-auth.lua

	$(INSTALL) COPYRIGHT $(INST_CONFDIR)/COPYRIGHT
	$(INSTALL) README.md $(INST_CONFDIR)/README.md
	$(INSTALL) bin/apisix $(INST_BINDIR)/apisix

test:
	prove -I../test-nginx/lib -r -s t/
