COMPOSE = docker compose -f docker-compose.yml
ARTIFACTS = artifacts
REQUESTS = $(ARTIFACTS)/requests

.PHONY: run logs analyze down

run:
	mkdir -p $(ARTIFACTS)
	$(COMPOSE) up --build -d apisix elasticsearch
	@$(COMPOSE) run --rm client > $(ARTIFACTS)/client.log || { status=$$?; $(MAKE) logs; exit $$status; }
	$(MAKE) logs
	$(MAKE) analyze

logs:
	$(COMPOSE) logs --no-color apisix > $(ARTIFACTS)/apisix.log
	$(COMPOSE) logs --no-color elasticsearch > $(ARTIFACTS)/elasticsearch.log

analyze:
	@while read -r trace_id name method cache; do \
		grep -F "trace=$$trace_id" $(ARTIFACTS)/client.log >/dev/null; \
		grep -F "trace=$$trace_id client_method=$$method" $(ARTIFACTS)/apisix.log >/dev/null; \
		case "$$name" in \
			query-miss|post-miss|query-auth-1|query-auth-2|post-auth-1|post-auth-2) \
				grep -F "$$trace_id" $(ARTIFACTS)/elasticsearch.log >/dev/null ;; \
			query-hit|post-hit|query-no-content-type) \
				! grep -F "$$trace_id" $(ARTIFACTS)/elasticsearch.log >/dev/null ;; \
		esac; \
	done < $(REQUESTS)
	@printf 'validated %s correlated client/APISIX/Elasticsearch requests\n' "$$(wc -l < $(REQUESTS))"

down:
	$(COMPOSE) down --volumes
