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
	"bytes"
	"context"
	"fmt"
	"strings"

	"github.com/chaos-mesh/chaos-mesh/api/v1alpha1"
	"github.com/onsi/gomega"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/remotecommand"
	kubectlscheme "k8s.io/kubectl/pkg/scheme"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/config"
)

type clientSet struct {
	ctrlCli client.Client
	kubeCli *kubernetes.Clientset
}

func initClientSet(g *gomega.WithT) *clientSet {
	scheme := runtime.NewScheme()
	v1alpha1.AddToScheme(scheme)

	restConfig := config.GetConfigOrDie()
	ctrlCli, err := client.New(restConfig, client.Options{Scheme: scheme})
	g.Expect(err).To(gomega.BeNil())
	kubeCli, err := kubernetes.NewForConfig(restConfig)
	g.Expect(err).To(gomega.BeNil())

	return &clientSet{ctrlCli, kubeCli}
}

func getPod(g *gomega.WithT, cli client.Client, listOption client.MatchingLabels) *corev1.Pod {
	pod := &corev1.Pod{}
	err := cli.List(context.Background(), pod, listOption)
	g.Expect(err).To(gomega.BeNil())
	return pod
}

func execInPod(cli *kubernetes.Clientset, pod *corev1.Pod, cmd string) string {
	name := pod.GetName()
	namespace := pod.GetNamespace()
	// only get the first container, no harm for now
	containerName := pod.Spec.Containers[0].Name

	req := cli.CoreV1().RESTClient().Post().
		Resource("pods").
		Name(name).
		Namespace(namespace).
		SubResource("exec")

	req.VersionedParams(&corev1.PodExecOptions{
		Container: containerName,
		Command:   []string{"/bin/sh", "-c", cmd},
		Stdin:     false,
		Stdout:    true,
		Stderr:    true,
		TTY:       false,
	}, kubectlscheme.ParameterCodec)

	var stdout, stderr bytes.Buffer
	exec, err := remotecommand.NewSPDYExecutor(config.GetConfigOrDie(), "POST", req.URL())
	if err != nil {
		panic(fmt.Sprintf("error: %s\nin creating NewSPDYExecutor for pod %s/%s", err.Error(), namespace, name))
	}
	err = exec.Stream(remotecommand.StreamOptions{
		Stdin:  nil,
		Stdout: &stdout,
		Stderr: &stderr,
	})
	if stderr.String() != "" {
		panic(fmt.Sprintf("error: %s\npod: %s\ncommand: %s", strings.TrimSuffix(stderr.String(), "\n"), pod.Name, cmd))
	}
	if err != nil {
		panic(fmt.Sprintf("error: %s\nin streaming remotecommand: pod: %s/%s, command: %s", err.Error(), namespace, pod.Name, cmd))
	}
	return stdout.String()
}
