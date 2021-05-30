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
	"net/http"
	"strconv"
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

func createEtcdDelayChaos(delay int) *v1alpha1.NetworkChaos {
	return &v1alpha1.NetworkChaos{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "etcd-delay",
			Namespace: metav1.NamespaceDefault,
		},
		Spec: v1alpha1.NetworkChaosSpec{
			Selector: v1alpha1.SelectorSpec{
				LabelSelectors: map[string]string{"app": "etcd"},
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

func setRouteMultipleTimes(t *testing.T, e *httpexpect.Expect, times int, status httpexpect.StatusRange) time.Duration {
	now := time.Now()
	timeLast := now
	var timeList []string
	for i := 0; i < times; i++ {
		utils.SetRoute(e, status)
		timeList = append(timeList, time.Now().Sub(timeLast).String())
		timeLast = time.Now()
	}
	t.Logf("takes %v separately", timeList)
	return time.Now().Sub(now) / time.Duration(times)
}

func TestAPISIXDelayWhenAddEtcdDelay(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	g := NewWithT(t)
	e := httpexpect.New(t, utils.Host)
	cliSet := utils.InitClientSet(g)

	defer func() {
		t.Logf("restore test environment")

		chaosList := &v1alpha1.NetworkChaosList{}
		err := cliSet.CtrlCli.List(ctx, chaosList)
		g.Expect(err).To(BeNil())
		for _, chaos := range chaosList.Items {
			cliSet.CtrlCli.Delete(ctx, &chaos)
		}

		t.Log("########################################################################")
		time.Sleep(3 * time.Minute)
		utils.DeleteRoute(e)
		utils.RestartWithBash(g, utils.ReAPISIXFunc)
	}()

	// check if everything works
	utils.SetRoute(e, http.StatusCreated)
	utils.GetRouteList(e, http.StatusOK)
	listOption := client.MatchingLabels{"app": "apisix-gw"}
	apisixPod := utils.GetPod(g, cliSet.CtrlCli, metav1.NamespaceDefault, listOption)

	// get default
	t.Run("get default apisix delay", func(t *testing.T) {
		setDuration := setRouteMultipleTimes(t, e, 5, httpexpect.Status2xx)
		t.Logf("set route cost time: %v", setDuration)
		g.Expect(setDuration < 15*time.Millisecond).To(BeTrue())

		errorLog, err := utils.Log(apisixPod, cliSet.KubeCli)
		g.Expect(err).To(BeNil())
		g.Expect(strings.Contains(errorLog, "error")).To(BeFalse())
	})

	// 30ms delay
	t.Run("generate a 30ms delay between etcd and apisix", func(t *testing.T) {
		chaos := createEtcdDelayChaos(30)
		err := cliSet.CtrlCli.Create(ctx, chaos.DeepCopy())
		g.Expect(err).To(BeNil())
		time.Sleep(1 * time.Second)

		setDuration := setRouteMultipleTimes(t, e, 5, httpexpect.Status2xx)
		t.Logf("set route cost time: %v", setDuration)
		g.Expect(setDuration < 400*time.Millisecond).To(BeTrue())

		errorLog, err := utils.Log(apisixPod, cliSet.KubeCli)
		g.Expect(err).To(BeNil())
		g.Expect(strings.Contains(errorLog, "error")).To(BeFalse())

		err = cliSet.CtrlCli.Delete(ctx, chaos.DeepCopy())
		g.Expect(err).To(BeNil())
		time.Sleep(1 * time.Second)
	})

	// 300ms delay
	t.Run("generate a 300ms delay between etcd and apisix", func(t *testing.T) {
		chaos := createEtcdDelayChaos(300)
		err := cliSet.CtrlCli.Create(ctx, chaos.DeepCopy())
		g.Expect(err).To(BeNil())
		time.Sleep(1 * time.Second)

		setDuration := setRouteMultipleTimes(t, e, 5, httpexpect.Status2xx)
		t.Logf("set route cost time: %v", setDuration)
		g.Expect(setDuration < 4*time.Second).To(BeTrue())

		errorLog, err := utils.Log(apisixPod, cliSet.KubeCli)
		g.Expect(err).To(BeNil())
		g.Expect(strings.Contains(errorLog, "error")).To(BeFalse())

		err = cliSet.CtrlCli.Delete(ctx, chaos.DeepCopy())
		g.Expect(err).To(BeNil())
		time.Sleep(1 * time.Second)
	})

	// 3s delay and cause error
	t.Run("generate a 3s delay between etcd and apisix", func(t *testing.T) {
		chaos := createEtcdDelayChaos(3000)
		err := cliSet.CtrlCli.Create(ctx, chaos.DeepCopy())
		g.Expect(err).To(BeNil())
		time.Sleep(1 * time.Second)

		setDuration := setRouteMultipleTimes(t, e, 2, httpexpect.Status5xx)
		t.Logf("set route cost time: %v", setDuration)

		errorLog, err := utils.Log(apisixPod, cliSet.KubeCli)
		g.Expect(err).To(BeNil())
		g.Expect(strings.Contains(errorLog, "error")).To(BeTrue())

		err = cliSet.CtrlCli.Delete(ctx, chaos.DeepCopy())
		g.Expect(err).To(BeNil())
	})
}
