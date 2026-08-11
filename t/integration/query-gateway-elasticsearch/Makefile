COMPOSE = docker compose -f docker-compose.yml
ARTIFACTS = artifacts
TRACE_ID = $$(cat $(ARTIFACTS)/trace_id)

.PHONY: run logs analyze down

run:
	mkdir -p $(ARTIFACTS)
	$(COMPOSE) up --build -d apisix elasticsearch
	$(COMPOSE) run --rm client | tee $(ARTIFACTS)/client.log
	$(MAKE) logs
	$(MAKE) analyze

logs:
	$(COMPOSE) logs --no-color apisix > $(ARTIFACTS)/apisix.log
	$(COMPOSE) logs --no-color elasticsearch > $(ARTIFACTS)/elasticsearch.log

analyze:
	@trace_id='$(TRACE_ID)'; \
	printf 'trace=%s\n' "$$trace_id"; \
	printf '\nCLIENT\n'; grep "$$trace_id" $(ARTIFACTS)/client.log || true; \
	printf '\nAPISIX\n'; grep "$$trace_id" $(ARTIFACTS)/apisix.log || true; \
	printf '\nELASTICSEARCH\n'; grep "$$trace_id" $(ARTIFACTS)/elasticsearch.log || true

down:
	$(COMPOSE) down --volumes
