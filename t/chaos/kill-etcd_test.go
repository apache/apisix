/*
 * Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements.  See the NOTICE file distributed with
 * this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0
 * (the "License"); you may not use this file except in compliance with
 * the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package chaos

import (
	"fmt"
	"net/http"
	"os/exec"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/gavv/httpexpect/v2"
	. "github.com/onsi/gomega"
)

var (
	token = "edd1c9f034335f136f87ad84b625c8f1"
	host  = "http://127.0.0.1:9080"
)

type httpTestCase struct {
	E            *httpexpect.Expect
	Method       string
	Path         string
	Body         string
	Headers      map[string]string
	ExpectStatus int
	ExpectBody   string
}

func caseCheck(tc httpTestCase) *httpexpect.Response {
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

	if tc.ExpectBody != "" {
		resp.Body().Contains(tc.ExpectBody)
	}

	return resp
}

func setRoute(e *httpexpect.Expect, expectStatus int) {
	caseCheck(httpTestCase{
		E:       e,
		Method:  http.MethodPut,
		Path:    "/apisix/admin/routes/1",
		Headers: map[string]string{"X-API-KEY": token},
		Body: `{
			"uri": "/hello",
			"host": "foo.com",
			"plugins": {
				"prometheus": {}
			},
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
		Method:       http.MethodGet,
		Path:         "/hello",
		Headers:      map[string]string{"Host": "foo.com"},
		ExpectStatus: expectStatus,
	})
}

func deleteRoute(e *httpexpect.Expect, expectStatus int) {
	caseCheck(httpTestCase{
		E:            e,
		Method:       http.MethodDelete,
		Path:         "/apisix/admin/routes/1",
		Headers:      map[string]string{"X-API-KEY": token},
		ExpectStatus: expectStatus,
	})
}

func testPrometheusEtcdMetric(e *httpexpect.Expect, expectEtcd int) {
	caseCheck(httpTestCase{
		E:          e,
		Method:     http.MethodGet,
		Path:       "/apisix/prometheus/metrics",
		ExpectBody: fmt.Sprintf("apisix_etcd_reachable %d", expectEtcd),
	})
}

// get the first line which contains the key
func getPrometheusMetric(e *httpexpect.Expect, g *WithT, key string) string {
	resp := caseCheck(httpTestCase{
		E:      e,
		Method: http.MethodGet,
		Path:   "/apisix/prometheus/metrics",
	})
	resps := strings.Split(resp.Body().Raw(), "\n")
	var targetLine string
	for _, line := range resps {
		if strings.Contains(line, key) {
			targetLine = line
			break
		}
	}
	targetSlice := strings.Fields(targetLine)
	g.Expect(len(targetSlice) == 2).To(BeTrue())
	return targetSlice[1]
}

func getIngressBandwidthPerSecond(e *httpexpect.Expect, g *WithT) float64 {
	key := "apisix_bandwidth{type=\"ingress\","
	bandWidthString := getPrometheusMetric(e, g, key)
	bandWidthStart, err := strconv.ParseFloat(bandWidthString, 64)
	g.Expect(err).To(BeNil())
	// after etcd got killed, it would take longer time to get the metrics
	// so need to calculate the duration
	timeStart := time.Now()

	time.Sleep(1 * time.Second)
	bandWidthString = getPrometheusMetric(e, g, key)
	bandWidthEnd, err := strconv.ParseFloat(bandWidthString, 64)
	g.Expect(err).To(BeNil())
	duration := time.Now().Sub(timeStart)

	return (bandWidthEnd - bandWidthStart) / duration.Seconds()
}

func runCommand(t *testing.T, cmd string) string {
	out, err := exec.Command("bash", "-c", cmd).CombinedOutput()
	if err != nil {
		t.Fatalf("fail to run command %s: %s, %s", cmd, err.Error(), out)
	}
	return string(out)
}

func roughCompare(a float64, b float64) bool {
	ratio := a / b
	if ratio < 1.3 && ratio > 0.7 {
		return true
	}
	return false
}

type silentPrinter struct {
	logger httpexpect.Logger
}

func newSilentPrinter(logger httpexpect.Logger) silentPrinter {
	return silentPrinter{logger}
}

// Request implements Printer.Request.
func (p silentPrinter) Request(req *http.Request) {
}

// Response implements Printer.Response.
func (silentPrinter) Response(*http.Response, time.Duration) {
}

func TestGetSuccessWhenEtcdKilled(t *testing.T) {
	g := NewWithT(t)
	e := httpexpect.New(t, host)

	eSilent := httpexpect.WithConfig(httpexpect.Config{
		BaseURL:  host,
		Reporter: httpexpect.NewAssertReporter(t),
		Printers: []httpexpect.Printer{
			newSilentPrinter(t),
		},
	})

	// check if everything works
	setRoute(e, http.StatusCreated)

	// to avoid route haven't been set yet
	time.Sleep(1 * time.Second)
	getRoute(e, http.StatusOK)
	testPrometheusEtcdMetric(e, 1)

	// run in background
	go func() {
		for {
			go getRoute(eSilent, http.StatusOK)
			time.Sleep(100 * time.Millisecond)
		}
	}()

	// wait 5 second to let first route access returns
	time.Sleep(5 * time.Second)
	bpsBefore := getIngressBandwidthPerSecond(e, g)
	g.Expect(bpsBefore).NotTo(BeZero())

	podName := runCommand(t, "kubectl get pod -l app=apisix-gw -o 'jsonpath={..metadata.name}'")
	t.Run("error log not contains etcd error", func(t *testing.T) {
		errorLog := runCommand(t, fmt.Sprintf("kubectl exec -it %s -- cat logs/error.log", podName))
		g.Expect(strings.Contains(errorLog, "failed to fetch data from etcd")).To(BeFalse())
	})

	// TODO: use client-go
	// apply chaos to kill all etcd pods
	t.Log("kill all etcd pods")
	_ = runCommand(t, "kubectl apply -f kill-etcd.yaml")
	time.Sleep(3 * time.Second)

	// fail to set route since etcd is all killed
	// while get route could still succeed
	setRoute(e, http.StatusInternalServerError)
	getRoute(e, http.StatusOK)
	testPrometheusEtcdMetric(e, 0)

	t.Run("error log contains etcd error", func(t *testing.T) {
		errorLog := runCommand(t, fmt.Sprintf("kubectl exec -it %s -- cat logs/error.log", podName))
		g.Expect(strings.Contains(errorLog, "failed to fetch data from etcd")).To(BeTrue())
	})

	bpsAfter := getIngressBandwidthPerSecond(e, g)
	t.Run("ingress bandwidth per second not change much", func(t *testing.T) {
		t.Logf("bps before: %f, after: %f", bpsBefore, bpsAfter)
		g.Expect(roughCompare(bpsBefore, bpsAfter)).To(BeTrue())
	})
}
