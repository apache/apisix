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

FROM golang:1.24 AS builder
WORKDIR /workspace
COPY . .
RUN CGO_ENABLED=0 go build -mod=mod -o /server ./cmd/

FROM ubuntu:20.04
RUN groupadd -r app && useradd -r -g app -m app
COPY --from=builder /server /server
RUN chown app:app /server
USER app
EXPOSE 8080
ENTRYPOINT ["/server"]
