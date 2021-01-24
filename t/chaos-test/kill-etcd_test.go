// Licensed to the Apache Software Foundation (ASF) under one or more
// contributor license agreements.  See the NOTICE file distributed with
// this work for additional information regarding copyright ownership.
// The ASF licenses this file to You under the Apache License, Version 2.0
// (the "License"); you may not use this file except in compliance with
// the License.  You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package chaos

import (
	"net/http"
	"os/exec"
	"testing"

	"github.com/gavv/httpexpect/v2"
)

var (
	token = "edd1c9f034335f136f87ad84b625c8f1"
	host  = "http://10.253.0.11:9080"
)

type httpTestCase struct {
	E            *httpexpect.Expect
	Method       string
	Path         string
	Body         string
	Headers      map[string]string
	ExpectStatus int
}

func caseCheck(tc httpTestCase) {
	e := tc.E
	var req *httpexpect.Request
	switch tc.Method {
	case http.MethodGet:
		req = e.GET(tc.Path)
	case http.MethodPut:
		req = e.PUT(tc.Path)
	default:
	}

	if req == nil {
		panic("fail to init request")
	}
	for key, val := range tc.Headers {
		req.WithHeader(key, val)
	}
	if tc.Body != "" {
		req.WithText(tc.Body)
	}

	resp := req.Expect()
	if tc.ExpectStatus != 0 {
		resp.Status(tc.ExpectStatus)
	}
}

func setRoute(e *httpexpect.Expect, expectStatus int) {
	caseCheck(httpTestCase{
		E:       e,
		Path:    "/apisix/admin/routes/1",
		Headers: map[string]string{"X-API-KEY": token},
		Body: `{
			"uri": "/hello",
			"host": "foo.com",
			"upstream": {
				"nodes": {
					"bar.org": 1
				},
				"type": "roundrobin"
			}
		}`,
		ExpectStatus: expectStatus,
	})
}

func getRoute(e *httpexpect.Expect, expectStatus int) {
	caseCheck(httpTestCase{
		E:            e,
		Path:         "/hello",
		Headers:      map[string]string{"Host": "foo.com"},
		ExpectStatus: expectStatus,
	})
}

func TestGetSuccessWhenEtcdKilled(t *testing.T) {
	e := httpexpect.New(t, host)

	// check if everything works
	setRoute(e, http.StatusOK)
	getRoute(e, http.StatusOK)

	// TODO: use client-go
	// apply chaos to kill all etcd pods
	_, err := exec.Command("kubectl apply kill-etcd.yaml").CombinedOutput()
	if err != nil {
		panic("fail to apply chaos yaml")
	}

	// fail to set route since etcd is all killed
	// while get route could still succeed
	setRoute(e, http.StatusInternalServerError)
	getRoute(e, http.StatusOK)
}
