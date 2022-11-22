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

package killetcd

import (
	"context"
	"fmt"
	"net/http"
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

var (
	bandwidthBefore float64
	durationBefore  float64
	bpsBefore       float64
	bandwidthAfter  float64
	durationAfter   float64
	bpsAfter        float64
)

func getEtcdKillChaos() *v1alpha1.PodChaos {
	return &v1alpha1.PodChaos{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "kill-etcd",
			Namespace: metav1.NamespaceDefault,
		},
		Spec: v1alpha1.PodChaosSpec{
			Selector: v1alpha1.SelectorSpec{
				LabelSelectors: map[string]string{"app.kubernetes.io/instance": "etcd"},
			},
			Action: v1alpha1.PodKillAction,
			Mode:   v1alpha1.AllPodMode,
			Scheduler: &v1alpha1.SchedulerSpec{
				Cron: "@every 10m",
			},
		},
	}
}

var _ = ginkgo.Describe("Test Get Success When Etcd Got Killed", func() {
	e := httpexpect.New(ginkgo.GinkgoT(), utils.Host)
	eDataPanel := httpexpect.New(ginkgo.GinkgoT(), utils.DataPanelHost)
	ePrometheus := httpexpect.New(ginkgo.GinkgoT(), utils.PrometheusHost)

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

	stopChan := make(chan bool)

	ginkgo.It("setup prometheus metrics public API", func() {
		utils.SetPrometheusMetricsPublicAPI(e)
	})

	ginkgo.It("check if everything works", func() {
		utils.SetRoute(e, httpexpect.Status2xx)
		utils.GetRouteList(e, http.StatusOK)

		utils.WaitUntilMethodSucceed(eDataPanel, http.MethodGet, 1)
		utils.TestPrometheusEtcdMetric(ePrometheus, 1)
	})

	ginkgo.It("run request in background", func() {
		go func() {
			defer ginkgo.GinkgoRecover()
			for {
				go func() {
					defer ginkgo.GinkgoRecover()
					utils.GetRoute(eDataPanel, http.StatusOK)
				}()
				time.Sleep(100 * time.Millisecond)
				stopLoop := false
				select {
				case <-stopChan:
					stopLoop = true
				default:
				}
				if stopLoop {
					break
				}
			}
		}()
	})
	// wait 1 seconds to let first route access returns
	time.Sleep(1 * time.Second)

	ginkgo.It("get stats before kill etcd", func() {
		timeStart := time.Now()
		bandwidthBefore, durationBefore = utils.GetEgressBandwidthPerSecond(ePrometheus)
		bpsBefore = bandwidthBefore / durationBefore
		gomega.Expect(bpsBefore).NotTo(gomega.BeZero())

		errorLog, err := utils.Log(apisixPod, cliSet.KubeCli, timeStart)
		gomega.Expect(err).To(gomega.BeNil())
		gomega.Ω(errorLog).ShouldNot(gomega.ContainSubstring("no healthy etcd endpoint available"))
	})

	// apply chaos to kill all etcd pods
	ginkgo.It("kill all etcd pods", func() {
		chaos := getEtcdKillChaos()
		err := cliSet.CtrlCli.Create(context.Background(), chaos.DeepCopy())
		gomega.Expect(err).To(gomega.BeNil())
		time.Sleep(3 * time.Second)
	})

	// fail to set route since etcd is all killed
	// while get route could still succeed
	ginkgo.It("get stats after kill etcd", func() {
		timeStart := time.Now()
		utils.SetRoute(e, httpexpect.Status5xx)
		utils.GetRoute(eDataPanel, http.StatusOK)
		utils.TestPrometheusEtcdMetric(ePrometheus, 0)

		bandwidthAfter, durationAfter = utils.GetEgressBandwidthPerSecond(ePrometheus)
		bpsAfter = bandwidthAfter / durationAfter

		errorLog, err := utils.Log(apisixPod, cliSet.KubeCli, timeStart)
		gomega.Expect(err).To(gomega.BeNil())
		gomega.Ω(errorLog).Should(gomega.ContainSubstring("invalid response code: 502"))
	})

	ginkgo.It("ingress bandwidth per second not change much", func() {
		fmt.Fprintf(ginkgo.GinkgoWriter, "bandwidth before: %f, after: %f\n", bandwidthBefore, bandwidthAfter)
		fmt.Fprintf(ginkgo.GinkgoWriter, "duration before: %f, after: %f\n", durationBefore, durationAfter)
		fmt.Fprintf(ginkgo.GinkgoWriter, "bps before: %f, after: %f\n", bpsBefore, bpsAfter)
		gomega.Expect(utils.RoughCompare(bpsBefore, bpsAfter)).To(gomega.BeTrue())
	})

	ginkgo.It("restore test environment", func() {
		stopChan <- true
		cliSet.CtrlCli.Delete(context.Background(), getEtcdKillChaos())
		utils.WaitUntilMethodSucceed(e, http.MethodPut, 5)
		utils.DeleteRoute(e)
	})
})
