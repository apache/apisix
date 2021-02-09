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
)

func createEtcdKillChaos(g *WithT, cli client.Client) {
	chaos := &v1alpha1.PodChaos{
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

	err := cli.Create(context.Background(), chaos)
	g.Expect(err).To(BeNil())
}

func TestGetSuccessWhenEtcdKilled(t *testing.T) {
	g := NewWithT(t)
	e := httpexpect.New(t, host)
	cliSet := initClientSet(g)

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

	listOption := client.MatchingLabels{"app": "apisix-gw"}
	apisixPod := getPod(g, cliSet.ctrlCli, metav1.NamespaceDefault, listOption)

	t.Run("error log not contains etcd error", func(t *testing.T) {
		errorLog := execInPod(g, cliSet.kubeCli, apisixPod, "cat logs/error.log")
		g.Expect(strings.Contains(errorLog, "failed to fetch data from etcd")).To(BeFalse())
	})

	// apply chaos to kill all etcd pods
	t.Run("kill all etcd pods", func(t *testing.T) {
		createEtcdKillChaos(g, cliSet.ctrlCli)
		time.Sleep(3 * time.Second)
	})

	// fail to set route since etcd is all killed
	// while get route could still succeed
	setRoute(e, http.StatusInternalServerError)
	getRoute(e, http.StatusOK)
	testPrometheusEtcdMetric(e, 0)

	t.Run("error log contains etcd error", func(t *testing.T) {
		errorLog := execInPod(g, cliSet.kubeCli, apisixPod, "cat logs/error.log")
		g.Expect(strings.Contains(errorLog, "failed to fetch data from etcd")).To(BeTrue())
	})

	bpsAfter := getIngressBandwidthPerSecond(e, g)
	t.Run("ingress bandwidth per second not change much", func(t *testing.T) {
		t.Logf("bps before: %f, after: %f", bpsBefore, bpsAfter)
		g.Expect(roughCompare(bpsBefore, bpsAfter)).To(BeTrue())
	})
}
