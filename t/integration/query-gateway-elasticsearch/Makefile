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
