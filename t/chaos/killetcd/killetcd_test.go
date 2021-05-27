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
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/chaos-mesh/chaos-mesh/api/v1alpha1"
	"github.com/gavv/httpexpect/v2"
	. "github.com/onsi/gomega"
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

func createEtcdKillChaos() *v1alpha1.PodChaos {
	return &v1alpha1.PodChaos{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "kill-etcd",
			Namespace: metav1.NamespaceDefault,
		},
		Spec: v1alpha1.PodChaosSpec{
			Selector: v1alpha1.SelectorSpec{
				LabelSelectors: map[string]string{"app": "etcd"},
			},
			Action: v1alpha1.PodKillAction,
			Mode:   v1alpha1.AllPodMode,
			Scheduler: &v1alpha1.SchedulerSpec{
				Cron: "@every 10m",
			},
		},
	}
}

func TestGetSuccessWhenEtcdKilled(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	g := NewWithT(t)
	e := httpexpect.New(t, utils.Host)
	ePrometheus := httpexpect.New(t, utils.HostPrometheus)
	cliSet := utils.InitClientSet(g)
	stopChan := make(chan bool)

	defer func() {
		t.Logf("restore test environment")

		stopChan <- true
		chaosList := &v1alpha1.PodChaosList{}
		err := cliSet.CtrlCli.List(ctx, chaosList)
		g.Expect(err).To(BeNil())
		for _, chaos := range chaosList.Items {
			cliSet.CtrlCli.Delete(ctx, &chaos)
		}

		utils.DeleteRoute(e)
		utils.RestartWithBash(g, utils.ReEtcdFunc)
	}()

	eSilent := httpexpect.WithConfig(httpexpect.Config{
		BaseURL:  utils.Host,
		Reporter: httpexpect.NewAssertReporter(t),
		Printers: []httpexpect.Printer{
			utils.NewSilentPrinter(t),
		},
	})

	listOption := client.MatchingLabels{"app": "apisix-gw"}
	apisixPod := utils.GetPod(g, cliSet.CtrlCli, metav1.NamespaceDefault, listOption)

	t.Run("check if everything works", func(t *testing.T) {
		utils.SetRoute(e, httpexpect.Status2xx)
		utils.GetRouteList(e, http.StatusOK)
		time.Sleep(1 * time.Second)
		utils.GetRoute(e, http.StatusOK)
		utils.TestPrometheusEtcdMetric(ePrometheus, 1)
	})

	// run in background
	go func() {
		for {
			go utils.GetRoute(eSilent, http.StatusOK)
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
	// wait 1 seconds to let first route access returns
	time.Sleep(1 * time.Second)

	t.Run("get stats before kill etcd", func(t *testing.T) {
		bandwidthBefore, durationBefore = utils.GetIngressBandwidthPerSecond(ePrometheus, g)
		bpsBefore = bandwidthBefore / durationBefore
		g.Expect(bpsBefore).NotTo(BeZero())

		errorLog, err := utils.Log(apisixPod, cliSet.KubeCli)
		g.Expect(err).To(BeNil())
		g.Expect(strings.Contains(errorLog, "failed to fetch data from etcd")).To(BeFalse())
	})

	// apply chaos to kill all etcd pods
	t.Run("kill all etcd pods", func(t *testing.T) {
		chaos := createEtcdKillChaos()
		err := cliSet.CtrlCli.Create(ctx, chaos.DeepCopy())
		g.Expect(err).To(BeNil())
		time.Sleep(3 * time.Second)
	})

	// fail to set route since etcd is all killed
	// while get route could still succeed

	t.Run("get stats after kill etcd", func(t *testing.T) {
		utils.SetRoute(e, httpexpect.Status5xx)
		utils.GetRoute(e, http.StatusOK)
		utils.TestPrometheusEtcdMetric(ePrometheus, 0)

		bandwidthAfter, durationAfter = utils.GetIngressBandwidthPerSecond(ePrometheus, g)
		bpsAfter = bandwidthAfter / durationAfter

		errorLog, err := utils.Log(apisixPod, cliSet.KubeCli)
		g.Expect(err).To(BeNil())
		g.Expect(strings.Contains(errorLog, "failed to fetch data from etcd")).To(BeTrue())
	})

	t.Run("ingress bandwidth per second not change much", func(t *testing.T) {
		t.Logf("bandwidth before: %f, after: %f", bandwidthBefore, bandwidthAfter)
		t.Logf("duration before: %f, after: %f", durationBefore, durationAfter)
		t.Logf("bps before: %f, after: %f", bpsBefore, bpsAfter)
		g.Expect(utils.RoughCompare(bpsBefore, bpsAfter)).To(BeTrue())
	})
}
