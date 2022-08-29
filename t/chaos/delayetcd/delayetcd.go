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

package delayetcd

import (
	"context"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"github.com/chaos-mesh/chaos-mesh/api/v1alpha1"
	"github.com/gavv/httpexpect"
	"github.com/onsi/ginkgo"
	"github.com/onsi/gomega"
	v1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"

	"github.com/apache/apisix/t/chaos/utils"
)

func getEtcdDelayChaos(delay int) *v1alpha1.NetworkChaos {
	return &v1alpha1.NetworkChaos{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "etcd-delay",
			Namespace: metav1.NamespaceDefault,
		},
		Spec: v1alpha1.NetworkChaosSpec{
			Selector: v1alpha1.SelectorSpec{
				LabelSelectors: map[string]string{"app.kubernetes.io/instance": "etcd"},
			},
			Action: v1alpha1.DelayAction,
			Mode:   v1alpha1.AllPodMode,
			TcParameter: v1alpha1.TcParameter{
				Delay: &v1alpha1.DelaySpec{
					Latency: strconv.Itoa(delay) + "ms",
				},
			},
		},
	}
}

func setRouteMultipleTimes(e *httpexpect.Expect, times int, status httpexpect.StatusRange) time.Duration {
	now := time.Now()
	timeLast := now
	var timeList []string
	for i := 0; i < times; i++ {
		utils.SetRoute(e, status)
		timeList = append(timeList, time.Since(timeLast).String())
		timeLast = time.Now()
	}
	fmt.Fprintf(ginkgo.GinkgoWriter, "takes %v separately\n", timeList)
	return time.Since(now) / time.Duration(times)
}

func setRouteMultipleTimesIgnoreError(e *httpexpect.Expect, times int) (time.Duration, int) {
	now := time.Now()
	var resp *httpexpect.Response
	for i := 0; i < times; i++ {
		resp = utils.SetRouteIgnoreError(e)
	}
	// use status code of the last time is enough to show the accessibility of apisix
	return time.Since(now) / time.Duration(times), resp.Raw().StatusCode
}

func deleteChaosAndCheck(eSilent *httpexpect.Expect, cliSet *utils.ClientSet, chaos *v1alpha1.NetworkChaos) {
	err := cliSet.CtrlCli.Delete(context.Background(), chaos)
	gomega.Expect(err).To(gomega.BeNil())
	time.Sleep(1 * time.Second)

	var setDuration time.Duration
	var statusCode int
	for range [10]int{} {
		setDuration, statusCode = setRouteMultipleTimesIgnoreError(eSilent, 5)
		if setDuration < 15*time.Millisecond && statusCode == http.StatusOK {
			break
		}
		time.Sleep(5 * time.Second)
	}
	gomega.Ω(setDuration).Should(gomega.BeNumerically("<", 15*time.Millisecond))
	gomega.Ω(statusCode).Should(gomega.BeNumerically("==", http.StatusOK))
}

var _ = ginkgo.Describe("Test APISIX Delay When Add ETCD Delay", func() {
	ctx := context.Background()
	e := httpexpect.New(ginkgo.GinkgoT(), utils.Host)
	eDataPanel := httpexpect.New(ginkgo.GinkgoT(), utils.DataPanelHost)
	ePrometheus := httpexpect.New(ginkgo.GinkgoT(), utils.PrometheusHost)
	eSilent := utils.GetSilentHttpexpectClient()

	var cliSet *utils.ClientSet
	var apisixPod *v1.Pod
	var err error
	ginkgo.It("init client set", func() {
		cliSet, err = utils.InitClientSet()
		gomega.Expect(err).To(gomega.BeNil())
		listOption := client.MatchingLabels{"app": "apisix-gw"}
		apisixPods, err := utils.GetPods(cliSet.CtrlCli, metav1.NamespaceDefault, listOption)
		gomega.Expect(err).To(gomega.BeNil())
		gomega.Ω(len(apisixPods)).Should(gomega.BeNumerically(">", 0))
		apisixPod = &apisixPods[0]
	})

	ginkgo.It("setup prometheus metrics public API", func() {
		utils.SetPrometheusMetricsPublicAPI(e)
	})

	ginkgo.It("check if everything works", func() {
		utils.SetRoute(e, httpexpect.Status2xx)
		utils.GetRouteList(e, http.StatusOK)

		utils.WaitUntilMethodSucceed(eDataPanel, http.MethodGet, 1)
		utils.TestPrometheusEtcdMetric(ePrometheus, 1)
	})

	// get default
	ginkgo.It("get default apisix delay", func() {
		timeStart := time.Now()
		setDuration := setRouteMultipleTimes(eSilent, 5, httpexpect.Status2xx)
		gomega.Ω(setDuration).Should(gomega.BeNumerically("<", 15*time.Millisecond))

		errorLog, err := utils.Log(apisixPod, cliSet.KubeCli, timeStart)
		gomega.Expect(err).To(gomega.BeNil())
		gomega.Ω(errorLog).ShouldNot(gomega.ContainSubstring("error"))
	})

	// 30ms delay
	ginkgo.It("generate a 30ms delay between etcd and apisix", func() {
		timeStart := time.Now()
		chaos := getEtcdDelayChaos(30)
		err := cliSet.CtrlCli.Create(ctx, chaos)
		gomega.Expect(err).To(gomega.BeNil())
		time.Sleep(1 * time.Second)

		defer deleteChaosAndCheck(eSilent, cliSet, chaos)

		setDuration := setRouteMultipleTimes(eSilent, 5, httpexpect.Status2xx)
		gomega.Ω(setDuration).Should(gomega.BeNumerically("<", 400*time.Millisecond))

		errorLog, err := utils.Log(apisixPod, cliSet.KubeCli, timeStart)
		gomega.Expect(err).To(gomega.BeNil())
		gomega.Ω(errorLog).ShouldNot(gomega.ContainSubstring("error"))
	})

	// 300ms delay
	ginkgo.It("generate a 300ms delay between etcd and apisix", func() {
		timeStart := time.Now()
		chaos := getEtcdDelayChaos(300)
		err := cliSet.CtrlCli.Create(ctx, chaos)
		gomega.Expect(err).To(gomega.BeNil())
		time.Sleep(1 * time.Second)

		defer deleteChaosAndCheck(eSilent, cliSet, chaos)

		setDuration := setRouteMultipleTimes(eSilent, 5, httpexpect.Status2xx)
		gomega.Ω(setDuration).Should(gomega.BeNumerically("<", 4*time.Second))

		errorLog, err := utils.Log(apisixPod, cliSet.KubeCli, timeStart)
		gomega.Expect(err).To(gomega.BeNil())
		gomega.Ω(errorLog).ShouldNot(gomega.ContainSubstring("error"))
	})

	// 3s delay and cause error
	ginkgo.It("generate a 3s delay between etcd and apisix", func() {
		timeStart := time.Now()
		chaos := getEtcdDelayChaos(3000)
		err := cliSet.CtrlCli.Create(ctx, chaos)
		gomega.Expect(err).To(gomega.BeNil())
		time.Sleep(1 * time.Second)

		defer deleteChaosAndCheck(eSilent, cliSet, chaos)

		_ = setRouteMultipleTimes(e, 2, httpexpect.Status5xx)

		errorLog, err := utils.Log(apisixPod, cliSet.KubeCli, timeStart)
		gomega.Expect(err).To(gomega.BeNil())
		gomega.Ω(errorLog).Should(gomega.ContainSubstring("error"))
	})

	ginkgo.It("restore test environment", func() {
		utils.WaitUntilMethodSucceed(e, http.MethodPut, 5)
		utils.DeleteRoute(e)
	})
})
