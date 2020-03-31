在k8s上面搭建apisix网关
# 
## 本地安装apisix
- 使用yum安装
```bash
yum install -y https://github.com/apache/incubator-apisix/releases/download/1.1/apisix-1.1-0.el7.noarch.rpm
```
## 本地安装dashboard
参见：[https://github.com/apache/incubator-apisix/tree/v1.1](https://github.com/apache/incubator-apisix/tree/v1.1) -- dashboard安装部分
或者 [https://blog.csdn.net/cyxinda/article/details/105099571](https://blog.csdn.net/cyxinda/article/details/105099571)--dashboard安装部分
## 工作目录结构：
如下是最终生成的工作目录
```python
workspace
|-- docker
|   |-- apisix
|   |   |-- apisix.dockerfile  #apisix的dockerfile
|   |   |-- config.yaml       #apisix的配置文件
|   |   |-- dashboard         #dashboard安装目录
|   |-- etcd
|   |   |-- etcd.conf.yml     #etcd的配置文件
|   |   |-- etcd.dockerfile   #etcd的dockerfile
|   |-- uuid                  #测试项目【uuid生成器】,普通的jar项目
|       |-- uuid-service-0.0.1-SNAPSHOT.jar
|       |-- uuid.dockerfile
|   |-- incubator-apisix-docker-master  #制作第一层docker镜像的目录
|-- k8s
    |-- apisix.yaml          #apisix的k8s编排文件
    |-- etcd.yaml            #etcd的k8s编排文件
    |-- uuid.yaml            #测试项目【uuid生成器】的k8s编排文件
```
## 制作apisix的docker镜像
- 下载incubator-apisix-docker到workspace/docker目录中
下载地址:     [https://github.com/apache/incubator-apisix-docker](https://github.com/apache/incubator-apisix-docker)
- build docker镜像：
在本地目录**workspace/docker/incubator-apisix-docker-master/** 下，执行如下build命令：
	```bash
	docker build -t harbor.aipo.lenovo.com/apisix/apisix:master-alpine -f alpine/Dockerfile alpine
	docker push harbor.aipo.lenovo.com/apisix/apisix:master-alpine
	```
	生成apisix的第一层镜像，并保存到了本地的harbor服务器上面
## 制作etcd的docker镜像
- 在目录**workspace/docker/etcd/** 中，复制etcd配置文件到当前目录
	```bash
	cp ../incubator-apisix-docker-master/example/etcd_conf/etcd.conf.yml .
	```
- 创建etcd的dockerfile：**etcd.dockerfile**，内容如下：
	```python
	FROM bitnami/etcd:3.3.13-r80
	COPY etcd.conf.yml /opt/bitnami/etcd/conf/etcd.conf.yml
	EXPOSE 2379 2380
	```
- 生成docker镜像
	```python
	docker build -t harbor.aipo.lenovo.com/apisix/etcd:3.3.13 -f etcd.dockerfile .
	docker push harbor.aipo.lenovo.com/apisix/etcd:3.3.13
	```
	生成etcd镜像，并将镜像保存到harbor上面
## 获取集群dns信息
- 在k8s集群的终端，获取集群域名
随便找到一个部署在k8s上面的pod，进入到容器内部：
	```bash
	kubectl -n kube-system exec -it pod/metrics-server-749c9798c6-zkg2m -- /bin/sh
	```
	在容器内部，查看dns配置：
	```bash
	[root@k8s-1 bin]# kubectl -n kube-system exec -it pod/metrics-server-749c9798c6-zkg2m -- /bin/sh
	/ # cat /etc/resolv.conf
	nameserver 10.1.0.10
	search kube-system.svc.cluster.local svc.cluster.local cluster.local openstacklocal
	options ndots:5
	/ #
	```
	其中kube-system.svc.cluster.local的结构是
	 > \<service_name\>\.\<namespace\>\.svc\.\<domain\>  
		每个部分的字段意思：
		> > service_name: 服务名称，就是定义 service 的时候取的名字
		> > namespace：service 所在 namespace 的名字
		> > domain：提供的域名后缀，比如默认的 cluster.local  
		可以参考：[https://cizixs.com/2017/04/11/kubernetes-intro-kube-dns/](https://cizixs.com/2017/04/11/kubernetes-intro-kube-dns/)

	domain这个字段就是我们要找的：在本集群中的值就是：**cluster.local**
	nameserver 10.1.0.10也可以知道dns的域名服务的ClusterIP为：10.1.0.10
- 获取集群dns的ClusterIP
check一下步骤一中，找到的ClusterIP是否正确
执行如下命令：
	```bash
	[root@k8s-1 bin]# kubectl -n kube-system get svc
	NAME                               TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)                  AGE
	etcd                               ClusterIP   None          <none>        2379/TCP                 133d
	kube-controller-manager-headless   ClusterIP   None          <none>        10252/TCP                133d
	kube-dns                           ClusterIP   10.1.0.10     <none>        53/UDP,53/TCP,9153/TCP   191d
	kube-scheduler-headless            ClusterIP   None          <none>        10251/TCP                133d
	kubelet                            ClusterIP   None          <none>        10250/TCP                133d
	kubernetes-dashboard               NodePort    10.1.213.19   <none>        443:30003/TCP            157d
	metrics-server                     ClusterIP   10.1.185.71   <none>        443/TCP                  133d
	tiller-deploy                      ClusterIP   10.1.55.173   <none>        44134/TCP                155d
	```
	kube-dns服务的ip就是k8s的DNS服务的ClusterIP，可以验证步骤1找到的ip与此步骤的ip是一致的：10.1.0.10

## 重新制作镜像
- 目的有两个：
 1. 加入dashboard
 2. 便于修改apisix的配置文件
 - 在<strong>workspace/docker/apisix/</strong>目录下
 1. 拷贝incubator-apisix-docker-master中的配置文件到当前目录
	```bash
	cp ../incubator-apisix-docker-master/example/apisix_conf/config.yaml .
	```
 2. 拷贝步骤【本地安装dashboard】中安装好的dashboard
	```bash
		cp -r /usr/local/apisix/dashboard .
	```	
- 修改apisix的配置文件
	```yaml
	apisix:
	  node_listen: 9080              # APISIX listening port
	  node_ssl_listen: 9443
	  enable_heartbeat: true
	  enable_admin: true
	  enable_debug: false
	  enable_ipv6: true
	  config_center: etcd             # etcd: use etcd to store the config value
	                                  # yaml: fetch the config value from local yaml file `/your_path/conf/apisix.yaml`
	  # allow_admin:                  # http://nginx.org/en/docs/http/ngx_http_access_module.html#allow
	  #   - 127.0.0.0/24              # If we don't set any IP list, then any IP access is allowed by default.
	  #   - "::/64"
	  # port_admin: 9180              # use a separate port
	  router:
	    http: 'radixtree_uri'         # radixtree_uri: match route by uri(base on radixtree)
	                                  # radixtree_host_uri: match route by host + uri(base on radixtree)
	                                  # r3_uri: match route by uri(base on r3)
	                                  # r3_host_uri: match route by host + uri(base on r3)
	
	    ssl: 'radixtree_sni'          # r3_sni: match route by SNI(base on r3)
	                                  # radixtree_sni: match route by SNI(base on radixtree)
	  # stream_proxy:                 # TCP/UDP proxy
	  #   tcp:                        # TCP proxy port list
	  #     - 9100
	  #     - 9101
	  #   udp:                        # UDP proxy port list
	  #     - 9200
	  #     - 9211
	  dns_resolver:                   # default DNS resolver, with disable IPv6 and enable local DNS
	    - 10.1.0.10
	
	  dns_resolver_valid: 30          # valid time for dns result 30 seconds
	
	  ssl:
	    enable: true
	    enable_http2: true
	    listen_port: 9443
	    ssl_protocols: "TLSv1 TLSv1.1 TLSv1.2 TLSv1.3"
	    ssl_ciphers: "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA:ECDHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES256-SHA256:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:DES-CBC3-SHA"
	
	nginx_config:                     # config for render the template to genarate nginx.conf
	  error_log: "logs/error.log"
	  error_log_level: "warn"         # warn,error
	  event:
	    worker_connections: 10620
	  http:
	    access_log: "logs/access.log"
	    keepalive_timeout: 60s         # timeout during which a keep-alive client connection will stay open on the server side.
	    client_header_timeout: 60s     # timeout for reading client request header, then 408 (Request Time-out) error is returned to the client
	    client_body_timeout: 60s       # timeout for reading client request body, then 408 (Request Time-out) error is returned to the client
	    send_timeout: 10s              # timeout for transmitting a response to the client.then the connection is closed
	    underscores_in_headers: "on"   # default enables the use of underscores in client request header fields
	    real_ip_header: "X-Real-IP"     # http://nginx.org/en/docs/http/ngx_http_realip_module.html#real_ip_header
	    real_ip_from:                  # http://nginx.org/en/docs/http/ngx_http_realip_module.html#set_real_ip_from
	      - 127.0.0.1
	      - 'unix:'
	
	etcd:
	  host: "http://etcd-service.saas.svc.cluster.local:12379"   # etcd address
	  prefix: "/apisix"               # apisix configurations prefix
	  timeout: 1                      # 1 seconds
	
	plugins:                          # plugin list
	  - example-plugin
	  - limit-req
	  - limit-count
	  - limit-conn
	  - key-auth
	  - prometheus
	  - node-status
	  - jwt-auth
	  - zipkin
	  - ip-restriction
	  - grpc-transcode
	  - serverless-pre-function
	  - serverless-post-function
	  - openid-connect
	  - proxy-rewrite
	
	stream_plugins:
	  - mqtt-proxy
	```
	修改两项：
	1. apisix.dns_resolver的值为10.1.0.10（前面获取到的k8s DNS的ClusterIP）
	2. etcd.host的值为http://<strong>etcd-service.saas.svc.cluster.local</strong> :12379
		1. etcd-service是k8s启动的etcd的service的名称，后文中会创建
	 	2. saas是etcd所属的命名空间
	 	3. cluster.local是前文中获取的k8s集群的域名
	 	4. 12379是etcd的service的port端口  
	 	
	**备注1：apisix依赖于nginx，而nginx的域名解析服务是需要独立配置的，nginx域名解析不会自动依赖系统设置的域名解析服务器**
	**备注2：k8s的域名解析服务，只能够解析本域下的命名，即以cluster.local结尾的命名**
- 创建apisix的dockerfile：**apisix.dockerfile**，内容如下：
	```bash
	FROM harbor.aipo.lenovo.com/apisix/apisix:master-alpine
	COPY config.yaml /usr/local/apisix/conf/config.yaml
	COPY dashboard /usr/local/apisix/dashboard
	EXPOSE 9080 9443
	```
- buid镜像
	```bash
	docker build -t harbor.aipo.lenovo.com/apisix/apisix:v1.1 -f apisix.dockerfile .
	docker push harbor.aipo.lenovo.com/apisix/apisix:v1.1
	```
## 创建k8s的编排文件
- etcd编排文件
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: saas
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: etcd-server
  namespace: saas #命名空间
  labels:
    app: etcd-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: etcd-server
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: etcd-server
    spec:
      containers:
      - name: etcd-server
        image: harbor.aipo.lenovo.com/apisix/etcd:3.3.13
        imagePullPolicy:  Always
        ports:
        - name: http
          containerPort: 2379 #容器对外暴露的端口
        - name: peer 
          containerPort: 2380
---
apiVersion: v1
kind: Service
metadata:
  name: etcd-service
  namespace: saas
spec:
  type: ClusterIP
  selector:
    app: etcd-server
  ports:
  - name: http
    port: 12379  #etcd的service暴露给其他服务的端口
    targetPort: 2379 #指向容器暴露的端口
```
	namespace为saas
- apisix的编排文件：
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: saas
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: apisix-server
  namespace: saas
  labels:
    app: apisix-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: apisix-server
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: apisix-server
    spec:
      containers:
      - name: apisix-server
        image: harbor.aipo.lenovo.com/apisix/apisix:v1.1
        imagePullPolicy:  Always
        ports:
        - name: http
          containerPort: 9080
        - name: https
          containerPort: 9443
---
apiVersion: v1
kind: Service
metadata:
  name: apisix-service
  namespace: saas
spec:
  type: NodePort #选择NodePort，暴露给k8s外部请求
  selector:
    app: apisix-server
  ports:
  - port: 80
    targetPort: 9080
    nodePort: 31191 #暴露给k8s外部的服务端口
```
## 启动服务
- 启动etcd服务
	```bash
	[root@k8s-1 k8s]# kubectl apply -f etcd.yaml
	namespace/saas created
	deployment.apps/etcd-server created
	service/etcd-service created
	```
	```bash
	[root@k8s-1 k8s]# kubectl get pods -n saas
	NAME                           READY   STATUS    RESTARTS   AGE
	etcd-server-69d9fbbcd7-dmxr2   1/1     Running   0          19s
	```
	可以看到etcd的pod已经启动了
- 启动apisix服务
	```bash
	[root@k8s-1 k8s]# kubectl apply -f apisix.yaml
	namespace/saas unchanged
	deployment.apps/apisix-server created
	service/apisix-service created
	```
	```bash
	[root@k8s-1 k8s]# kubectl get pods -n saas
	NAME                            READY   STATUS    RESTARTS   AGE
	apisix-server-8b4cb7ff9-7mst5   1/1     Running   0          3m41s
	etcd-server-69d9fbbcd7-dmxr2    1/1     Running   0          4m12s
	```
		可以看到apisix的pod已经启动了
## 验证
- 浏览器打开k8s集群的任意一台ip地址，如[http://10.110.149.172:31191/apisix/dashboard](http://10.110.149.172:31191/apisix/dashboard)
可以在页面上面看到
![在这里插入图片描述](https://img-blog.csdnimg.cn/20200327194655583.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L2N5eGluZGE=,size_16,color_FFFFFF,t_70)
页面上面可以正常添加route和upstream，表明搭建成功！


## 其他
- 附调试常用命令行
在调试k8s的调试过程中，用到了好多常用的k8s的命令，贴出来，供大家参考：
	```bash
	cd /root/username/workspace/docker/etcd
	docker build -t harbor.aipo.lenovo.com/apisix/etcd:3.3.13 -f etcd.dockerfile .
	docker rm -f etcd-server
	docker run -it --name etcd-server \
	 -p 23791:2379 \
	 -p 23801:2380 \
	 -d harbor.aipo.lenovo.com/apisix/etcd:3.3.13
	docker ps |grep etcd-server
	docker logs etcd-server
	 -------------------------------------------
	
	kubectl delete -f apisix.yaml
	kubectl apply -f etcd.yaml
	kubectl get pods -n saas -o wide
	kubectl logs pods/etcd-server-746d5b4cf7-th44j -c etcd-server --namespace=saas # --previous 该参数可以查看上一次启动的容器的日志，非常有用
	kubectl exec -it etcd-server-746d5b4cf7-k4bhv -c etcd-server -n saas /bin/bash 
	
	cd /root/username/workspace/docker/apisix
	docker build --no-cache -t harbor.aipo.lenovo.com/apisix/apisix:v1.1 -f apisix.dockerfile .
	docker push harbor.aipo.lenovo.com/apisix/apisix:v1.1
	
	cd /root/caoyong/apisix/k8s
	kubectl get pods -n saas -o wide
	kubectl get svc -n saas -o wide
	kubectl delete svc apisix-service -n saas
	kubectl delete pod apisix-server-88fbc7f99-gvnr4  -n saas
	kubectl delete -f apisix.yaml
	kubectl get endpoints -n saas -o wide
	kubectl apply -f apisix.yaml
	kubectl get pods -n saas -o wide
	kubectl get svc -n saas -o wide
	kubectl logs pods/apisix-server-8b4cb7ff9-7mst5 -c apisix-server  --namespace=saas
	kubectl exec -it  apisix-server-88fbc7f99-pf8sj -c apisix-server -n saas /bin/bash 
	```
	由service寻找pod的过程
	```bash
	kubectl get svc -n kube-system
	kubectl -n kube-system describe svc/metrics-server	
	kubectl -n kube-system get pod -l app=metrics-server	
	kubectl -n kube-system describe pod/kubernetes-dashboard-7844b55485-c2dxm	
	kubectl -n kube-system exec -it kubernetes-dashboard-7844b55485-c2dxm /bin/sh
	```
- 附可调试的etcd镜像
	- 需要下载etcd按照源码到本地，参考：[https://github.com/etcd-io/etcd/releases/tag/v3.4.5](https://github.com/etcd-io/etcd/releases/tag/v3.4.5)
	比如下在版本为v3.4.5的etcd，如下将ETCD_VER替换成v3.4.5即可
		```bash
		GOOGLE_URL=https://storage.googleapis.com/etcd
		GITHUB_URL=https://github.com/etcd-io/etcd/releases/download
		DOWNLOAD_URL=${GOOGLE_URL}
		
		rm -f /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz
		rm -rf /tmp/etcd-download-test && mkdir -p /tmp/etcd-download-test
		
		curl -L ${DOWNLOAD_URL}/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz -o /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz
		tar xzvf /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz -C /tmp/etcd-download-test --strip-components=1
		rm -f /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz
		
		/tmp/etcd-download-test/etcd --version
		/tmp/etcd-download-test/etcdctl version
		```
	- 创建一个工具比较齐全的docker，附centos.tools.dockerfile：
		```bash
		FROM centos:7.6.1810
		LABEL maintainer=caoyong1
		WORKDIR /root
		COPY *.repo /etc/yum.repos.d/
		#指定时区以及安装各种插件
		RUN cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && yum install kde-l10n-Chinese -y && yum install glibc-common -y && localedef -c -f UTF-8 -i zh_CN zh_CN.utf8 && mkdir services && yum clean all && yum makecache && yum install -y epel-release && yum clean all && yum makecache && yum -y install iputils && yum -y install net-tools.x86_64 && yum install -y redhat-lsb && yum -y install bridge-utils && yum -y install traceroute && yum -y install vim*
		#指定字符集
		ENV LANG zh_CN.UTF-8
		ENV LANGUAGE zh_CN.UTF-8
		ENV LC_ALL zh_CN.UTF-8
		```
	- 附本目录中的镜像源：wget http://mirrors.163.com/.help/CentOS7-Base-163.repo
		```bash
		docker build -t harbor.aipo.lenovo.com/apisix/centos:tools -f centos.tools.dockerfile .
		docker push harbor.aipo.lenovo.com/apisix/centos:tools
		```
	- 以上面的镜像为基础，创建工具比较全的etcd镜像源，附etcd3.4.5.dockerfile：
		```bash
		FROM harbor.aipo.lenovo.com/apisix/centos:tools
		WORKDIR /root
		COPY etcd.conf.yml /opt/bitnami/etcd/conf/etcd.conf.yml
		ADD  etcd-v3.4.5-linux-amd64.tar.gz .
		WORKDIR /root/etcd-v3.4.5-linux-amd64
		EXPOSE 2379 2380
		ENV ALLOW_NONE_AUTHENTICATION=yes
		ENTRYPOINT [ "./etcd","--config-file=/opt/bitnami/etcd/conf/etcd.conf.yml"
		```
