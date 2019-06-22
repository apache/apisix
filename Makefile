INST_PREFIX ?= /usr
INST_LIBDIR ?= $(INST_PREFIX)/lib64/lua/5.1
INST_LUADIR ?= $(INST_PREFIX)/share/lua/5.1
INST_BINDIR ?= /usr/bin
INSTALL ?= install


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
	./utils/update_nginx_conf_dev.sh
	sudo luarocks install apisix-*.rockspec --tree deps


### check:        Check Lua srouce code
.PHONY: check
check:
	luacheck -q lua
	./utils/lj-releng lua/*.lua lua/apisix/*.lua \
		lua/apisix/admin/*.lua \
		lua/apisix/core/*.lua \
		lua/apisix/plugins/*.lua > \
		/tmp/check.log 2>&1 || (cat /tmp/check.log && exit 1)


### run:          Start the apisix server
.PHONY: run
run:
	mkdir -p logs
	mkdir -p /tmp/cores/
	$$(which openresty) -p $$PWD/


### stop:         Stop the apisix server
.PHONY: stop
stop:
	$$(which openresty) -p $$PWD/ -s stop


### clean:        Remove generated files
.PHONY: clean
clean:
	rm -rf logs/


### reload:       Reload the apisix server
.PHONY: reload
reload:
	$$(which openresty) -p $$PWD/ -s reload


### install:      Install the apisix
.PHONY: install
install:
	$(INSTALL) -d /usr/local/apisix/logs/
	$(INSTALL) -d /usr/local/apisix/conf/cert
	$(INSTALL) conf/mime.types /usr/local/apisix/conf/mime.types
	$(INSTALL) conf/config.yaml /usr/local/apisix/conf/config.yaml
	$(INSTALL) conf/cert/apisix.* /usr/local/apisix/conf/cert/

	$(INSTALL) -d $(INST_LUADIR)/apisix/lua/apisix/core
	$(INSTALL) lua/*.lua $(INST_LUADIR)/apisix/lua/
	$(INSTALL) lua/apisix/core/*.lua $(INST_LUADIR)/apisix/lua/apisix/core/
	$(INSTALL) lua/apisix/*.lua $(INST_LUADIR)/apisix/lua/apisix/

	$(INSTALL) -d $(INST_LUADIR)/apisix/lua/apisix/plugins/prometheus/
	$(INSTALL) lua/apisix/plugins/prometheus/*.lua $(INST_LUADIR)/apisix/lua/apisix/plugins/prometheus/

	$(INSTALL) -d $(INST_LUADIR)/apisix/lua/apisix/plugins
	$(INSTALL) lua/apisix/plugins/*.lua $(INST_LUADIR)/apisix/lua/apisix/plugins/

	$(INSTALL) -d $(INST_LUADIR)/apisix/lua/apisix/admin
	$(INSTALL) lua/apisix/admin/*.lua $(INST_LUADIR)/apisix/lua/apisix/admin/

	$(INSTALL) COPYRIGHT $(INST_CONFDIR)/COPYRIGHT
	$(INSTALL) README.md $(INST_CONFDIR)/README.md
	$(INSTALL) bin/apisix $(INST_BINDIR)/apisix

test:
	prove -I../test-nginx/lib -r -s t/
