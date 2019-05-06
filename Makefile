
### help:		Show Makefile rules.
.PHONY: help
help:
	@echo Makefile rules:
	@echo
	@grep -E '^### [-A-Za-z0-9_]+:' Makefile | sed 's/###/   /'


### run:		Start the apimeta server
.PHONY: run
run:
	mkdir -p logs
	sudo $$(which openresty) -p $$PWD/


### stop:		Stop the apimeta server
.PHONY: stop
stop:
	sudo $$(which openresty) -p $$PWD/ -s stop


### clean:		Remove generated files
.PHONY: clean
clean:
	rm -rf logs/


### reload:		Reload the apimeta server
.PHONY: reload
reload:
	sudo $$(which openresty) -p $$PWD/ -s reload
