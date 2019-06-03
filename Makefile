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


### install:      Install the Apisix
.PHONY: install
install:
	$(INSTALL) -d $(INST_LUADIR)/apisix/logs/
	$(INSTALL) logs/placehold.txt $(INST_LUADIR)/apisix/logs/
	$(INSTALL) -d $(INST_LUADIR)/apisix/conf/
	$(INSTALL) conf/mime.types $(INST_LUADIR)/apisix/conf/mime.types
	$(INSTALL) conf/nginx.conf $(INST_LUADIR)/apisix/conf/nginx.conf
	./utils/install_nginx_conf.sh $(INST_LUADIR)/apisix/conf/config.yaml
	cp -r lua $(INST_LUADIR)/apisix/
	cp -r lua $(INST_LUADIR)/apisix/
	cp -r doc $(INST_LUADIR)/apisix/
	cp -r cli $(INST_LUADIR)/apisix/cli
	chmod 644 $(INST_LUADIR)/apisix/conf/config.yaml
	$(INSTALL) COPYRIGHT $(INST_LUADIR)/apisix/
	$(INSTALL) README.md $(INST_LUADIR)/apisix/
	$(INSTALL) README_CN.md $(INST_LUADIR)/apisix/
	$(INSTALL) cli/apisix.lua $(INST_BINDIR)/apisix

test:
	prove -I../test-nginx/lib -r -s t/
