find lua -type d | sort | awk '{print "$(INSTALL) -d $(INST_LUADIR)/apisix/" $0 "\n" "$(INSTALL) " $0 "/*.lua $(INST_LUADIR)/apisix/" $0 "/\n" }'
