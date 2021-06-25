<div dir="rtl">

<!--
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
-->

# أباتشي أبيسكس

<img src="https://svn.apache.org/repos/asf/comdev/project-logos/originals/apisix.svg" alt="APISIX logo" height="150px" align="right" />

[![Build Status](https://github.com/apache/apisix/workflows/build/badge.svg?branch=master)](https://github.com/apache/apisix/actions)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://github.com/apache/apisix/blob/master/LICENSE)

**أباتشي أبيسكس** هو عبارة عن بوابة ديناميكية وفي الوقت الفعلي وعالية الاداء

أباتشي أبيسكس توفر امتيازات حركة مرور كبيرة مثل (موازنة التحميل، المنبع الديناميكي، إصدار كناري، كسر الدائرة، المصادقة، إمكانية المراقبة، والمزيد.
يمكنك استخدام أباتشي أبيسكس للتعامل مع حركة المرور التقليدية شمالا-جنوبا
وأيضا بحركة شرق-غرب بين الخدمات.
يمكن استخدامه أيضا [كوحدة تحكم دخول k8s](https://github.com/apache/apisix-ingress-controller).

بنية الهيكل الفني لأباتشي أبيسكس:
![apisix](https://user-images.githubusercontent.com/81928799/114623300-be43e180-9cb7-11eb-8d69-c7c6ea494717.png)

## المجتمع

القائمة البريدية: أرسل بالبريد إلى dev-subscribe@apisix.apache.org

اتبع الرد للاشتراك في القائمة البريدية.

مجموعة QQ - 578997126

- [مساحة عمل Slack](https://join.slack.com/t/the-asf/shared_invite/zt-mrougyeu-2aG7BnFaV0VnAT9_JIUVaA) - تابع `#apisix` على Slack لمقابلة الفريق وطرح الأسئلة
- ![متابعة Twitter -](https://img.shields.io/twitter/follow/ApacheAPISIX?style=social) - تابعنا وتفاعل معنا باستخدام الهاشتاج  `#ApacheAPISIX`
- [bilibili فيديو](https://space.bilibili.com/551921247)
- **الاصدارات الأولى الجيدة**:
  - [اباتشي ابيسكس](https://github.com/apache/apisix/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22)
  - [وحدة تحكم الدخول أباتشي ابيسكس](https://github.com/apache/apisix-ingress-controller/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22)
  - [لوحة القيادة أباتشي ابيسكس](https://github.com/apache/apisix-dashboard/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22)
  - [مخطط خوذة أباتشي ابيسكس](https://github.com/apache/apisix-helm-chart/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22)
  - [توزيع أباتشي ابيسكس](https://github.com/apache/apisix-docker/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22)
  - [موقع ويب أباتشي ابيسكس](https://github.com/apache/apisix-website/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22)
  - [طائرة التحكم لـ أبيسكس](https://github.com/apache/apisix-control-plane/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22)

## السمات

•	يمكنك استخدام أباتشي أبيسكس كمدخل لحركة المرور لمعالجة جميع بيانات الأعمال ، بما في ذلك التوجيه الديناميكي ، والمنبع الديناميكي ، والشهادات الديناميكية ، واختبار A / B ، وإصدار الكناري ، والنشر الأزرق والأخضر ، ومعدل الحد ، والدفاع ضد الهجمات الضارة ، والمقاييس ، وإنذارات المراقبة ، وقابلية مراقبة الخدمة ، وحوكمة الخدمة ، وما إلى ذلك.

- **جميع المنصات**

 Native: النظام الأساسي غير المقيد ، لا يوجد قفل للبائع ، يمكن تشغيل APISIX من النظام الأساسي إلى Kubernetes.

•	بيئة التشغيل: يتم دعم كل من OpenResty و Tengine.

•	يدعم ARM64: لا تقلق بشأن قفل تقنية الأشعة تحت الحمراء.

- **متعدد البروتوكولات**

  - [TCP/UDP وكيل](docs/en/latest/stream-proxy.md): ديناميكي TCP/UDP وكيل.
  - [Dubbo وكيل](docs/en/latest/plugins/dubbo-proxy.md): ديناميكي HTTP to Dubbo وكيل.
  - [ديناميكي MQTT وكيل](docs/en/latest/plugins/mqtt-proxy.md): يدعم تحميل  MQTT بواسطة  `client_id`, وكلاهما يدعم  MQTT [3.1.\*](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html), [5.0](https://docs.oasis-open.org/mqtt/mqtt/v5.0/mqtt-v5.0.html).
  - [gRPC proxy](docs/en/latest/grpc-proxy.md):توكيل حركة مرور  gRPC .
  - [gRPC transcoding](docs/en/latest/plugins/grpc-transcode.md): يدعم تحويل ترميز البروتوكول بحيث يمكن للعملاء الوصول إلى واجهة برمجة تطبيقات gRPC الخاصة بك باستخدام  HTTP/JSON.
  - مقبس الويب الوكيل
  - بروتوكول الوكيل
  - الوكيل  Dubbo: Dubbo يعتمد على  Tengine.
  - HTTP(S)	وكيل إعادة التوجيه
  - [SSL](docs/en/latest/certificate.md): تحميل شهادة SSL ديناميكيًا.

- **ديناميكية كاملة**

  - [التحديثات الطارئة والإضافات الطارئة](docs/en/latest/plugins.md): يقوم باستمرار بتحديث التكوينات والإضافات دون إعادة التشغيل!
  - [إعادة كتابة الوكيل](docs/en/latest/plugins/proxy-rewrite.md):دعم إعادة كتابة المضيف، uri، المخطط، enable_websocket، رؤوس الطلب قبل الإرسال إلى المنبع.
  - [إعادة كتابة الاستجابة](docs/en/latest/plugins/response-rewrite.md): قم بتعيين رمز حالة الاستجابة المخصص والجسم والرأس للعميل.
  - [بدون خادم](docs/en/latest/plugins/serverless.md): استدعاء الوظائف في كل مرحلة في ابيسكس.
  - موازنة الحمل الديناميكية: موازنة تحميل دائرية مع الوزن.
  - موازنة التحميل المستندة إلى التجزئة: توازن الحمل مع جلسات التجزئة المتسقة.
  - [الفحوصات الصحية](docs/en/latest/health-check.md): قم بتمكين الفحص الصحي على عقدة المنبع وسيقوم تلقائيًا بتصفية العقد غير الصحية أثناء موازنة التحميل لضمان استقرار النظام.
  - قاطع الدائرة: تتبع ذكي لخدمات المنبع غير الصحية.
  - [مرآة الوكيل](docs/en/latest/plugins/proxy-mirror.md): توفر القدرة على عكس طلبات العميل
  - [تقسيم حركة المرور](docs/en/latest/plugins/traffic-split.md): يسمح للمستخدمين بتوجيه النسب المئوية بشكل متزايد من حركة المرور بين مختلف التدفقات.

- **التوجيه الدقيق**

  - [يدعم مطابقة المسار الكامل ومطابقة البادئة](docs/en/latest/router-radixtree.md#how-to-use-libradixtree-in-apisix)
  - [دعم جميع متغيرات Nginx المضمنة كشرط للتوجيه](docs/en/latest/router-radixtree.md#how-to-filter-route-by-nginx-builtin-variable), بحيث يمكنك استخدام  `ملفات تعريف الارتباط`, `args`, وما إلى ذلك. كظروف توجيه لتنفيذ إصدار canary ، واختبار A / B ، إلخ
  - دعم  [العديد من المشغلين كشروط حكم للتوجيه](https://github.com/iresty/lua-resty-radixtree#operator-list), على سبيل المثال  `{"arg_age", ">", 24}`
  - دعم  [وظيفة مطابقة الطريق المخصصة](https://github.com/iresty/lua-resty-radixtree/blob/master/t/filter-fun.t#L10)
  - IPv6: استخدم IPv6 لمطابقة المسار.
  - دعم  [TTL](docs/en/latest/admin-api.md#route)
  - [أولوية الدعم](docs/en/latest/router-radixtree.md#3-match-priority)
  - [دعم طلبات Http الدفعية](docs/en/latest/plugins/batch-requests.md)

- **الحماية**

  -المصادقات: [key-auth](docs/en/latest/plugins/key-auth.md), [JWT](docs/en/latest/plugins/jwt-auth.md), [basic-auth](docs/en/latest/plugins/basic-auth.md), [wolf-rbac](docs/en/latest/plugins/wolf-rbac.md)
  - [IP القائمة البيضاء/القائمة السوداء](docs/en/latest/plugins/ip-restriction.md)
  - [القائمة البيضاء للمراجع / القائمة السوداء](docs/en/latest/plugins/referer-restriction.md)
  - [IdP](docs/en/latest/plugins/openid-connect.md): دعم خدمات المصادقة الخارجية , مثل Auth0, okta, etc., يمكن للمستخدمين استخدام هذا للاتصال بـ OAuth 2.0 وطرق المصادقة الأخرى.
  - [حد-مطلوب](docs/en/latest/plugins/limit-req.md)
  - [حد-العد](docs/en/latest/plugins/limit-count.md)
  - [المحدد-التزامن](docs/en/latest/plugins/limit-conn.md)
  - Anti-ReDoS(التعبير العادي رفض الخدمة): سياسات مضمنة لـ Anti-ReDoS بدون تكوين.
  - [CORS](docs/en/latest/plugins/cors.md) تمكين CORS(مشاركة الموارد عبر الأصل) لواجهة برمجة التطبيقات الخاصة بك.
  - [URI حظر](docs/en/latest/plugins/uri-blocker.md): حظر طلب العميل عن طريق URI.
  - [طلب مدقق](docs/en/latest/plugins/request-validation.md)

- **OPS ودي**

  - أوبينتراكينج: دعم [أباتشي سكايواكينغ](docs/en/latest/plugins/skywalking.md)  [زيبكين](docs/en/latest/plugins/zipkin.md)
  - يعمل مع اكتشاف الخدمة الخارجية：بالإضافة إلى الخادم المدمج, فإنه يدعم أيضًا وضع  `Consul` و `Nacos` [DNS وضع الاكتشاف](https://github.com/apache/apisix/issues/1731#issuecomment-646392129), و [يوريكا](docs/en/latest/discovery.md)
  - المراقبة والقياسات: [بروميثيوس](docs/en/latest/plugins/prometheus.md)
  - التجميع: عُقد أبيسكس عديمة الحالة، وتقوم بإنشاء مجموعات لمركز التكوين، يرجى الرجوع إلى [etcd دليل المجموعات](https://etcd.io/docs/v3.4.0/op-guide/clustering/).
  - التوافر العالي: دعم تكوين عناوين etcd متعددة في نفس المجموعة.
  - [لوحة القيادة](https://github.com/apache/apisix-dashboard)
  - التحكم في الإصدار: يدعم التراجع عن العمليات.
  - CLI: بدء\ايقاف\اعادة تحميل أبيسكس من خلال سطر الأوامر.
  - [قائمة-ذاتية](docs/en/latest/stand-alone.md):يدعم تحميل قواعد المسار من ملف YAML المحلي ، وهو أكثر ملاءمة مثل تحت kubernetes (k8s).
  - [القاعدة العالمية](docs/en/latest/architecture-design/global-rule.md): تسمح بتشغيل أي مكون إضافي لجميع الطلبات، على سبيل المثال: معدل الحد، مرشح IP، إلخ.
  - أداء عالٍ: يصل معدل QPS أحادي النواة إلى 18 ألفًا بمتوسط تأخير أقل من 0.2 مللي ثانية
  - [حقن خاطئ](docs/en/latest/plugins/fault-injection.md)
  - [REST Admin API](docs/en/latest/admin-api.md): استخدام REST Admin API للتحكم ب أباتشي أبيسكس, والذي يسمح فقط 127.0.0.1 الوصول افتراضيا, يمكنك تعديل حقل  `allow_admin` حقل في `conf/config.yaml` لتحديد قائمة عناوين  IPs المسموح لها باستدعاء  Admin API. Also,لاحظ أيضًا أن Admin API تستخدم مصادقة المفتاح للتحقق من هوية المتصل. **`admin_key` حقل في `conf/config.yaml` يحتاج إلى تعديل قبل النشر لضمان الأمان**.
  - المسجلات الخارجية: تصدير سجلات الوصول إلى أدوات إدارة السجلات الخارجيةs. ([HTTP Logger](docs/en/latest/plugins/http-logger.md), [TCP Logger](docs/en/latest/plugins/tcp-logger.md), [Kafka Logger](docs/en/latest/plugins/kafka-logger.md), [UDP Logger](docs/en/latest/plugins/udp-logger.md))
  - [مخططات الخوذة](https://github.com/apache/apisix-helm-chart)

- **قابلة للتطوير بدرجة كبيرة**
  - [المكونات الإضافية المخصصة](docs/en/latest/plugin-develop.md): تسمح بربط المراحل الشائعة مثل `إعادة الكتابة`, `الوصول`, `مرشح العنوان`, `مرشح الجسم` and `السجل`, كما يسمح بربط `الموازنة` مرحلة.
  - خوارزميات موازنة الحمل المخصصة: يمكنك استخدام خوارزميات موازنة التحميل المخصصة أثناء  `الموازنة` مرحلة.
  - التوجيه المخصص: دعم المستخدمين لتنفيذ خوارزميات التوجيه بأنفسهم.

## البدء

### التكوين والتثبيت

تم تثبيت واختبار أبيسكس في الأنظمة التالية:

CentOS 7, Ubuntu 16.04, Ubuntu 18.04, Debian 9, Debian 10, macOS, **ARM64** Ubuntu 18.04

هناك عدة طرق لتثبيت إصدار أباتشي من أبيسكس:

1. تجميع الكود المصدر (ينطبق على جميع الأنظمة)

   - تبعيات وقت تشغيل التثبيت: OpenResty and etcd, و وتبعيات التجميع: luarocks. الرجوع إلى  [وثائق تبعيات التثبيت](docs/en/latest/install-dependencies.md)
   - قم بتنزيل أحدث حزمة إصدار لشفرة المصدر:

     ```shell
     $ mkdir apisix-2.6
     $ wget https://downloads.apache.org/apisix/2.6/apache-apisix-2.6-src.tgz
     $ tar zxvf apache-apisix-2.6-src.tgz -C apisix-2.6
     ```

   - تثبيت التبعيات ：

     ```shell
     $ make deps
     ```

   - تفقد نسخة الابيسكس:

     ```shell
     $ ./bin/apisix version
     ```

   - أبدأ أبيسكس:

     ```shell
     $ ./bin/apisix start
     ```

2. [Docker صورة](https://hub.docker.com/r/apache/apisix) （متطابق مع جميع الانظمة）

   بشكل افتراضي ، سيتم سحب أحدث حزمة إصدار أباتشي:

   ```shell
   $ docker pull apache/apisix
   ```

   لا تتضمن صورة Docker  `etcd`; يمكنك الرجوع الى [مثال تكوين عامل الإرساء](https://github.com/apache/apisix-docker/tree/master/example) لبدء مجموعة اختبار.

3. RPM حزمة（فقط ل CentOS 7）

   - تبعيات وقت تشغيل التثبيت: OpenResty, etcd and OpenSSL طور مكتبة, الرجوع الى [وثائق تبعيات تثبيت](docs/en/latest/install-dependencies.md#centos-7)
   - تثبيت أبيسكس：

   ```shell
   $ sudo yum install -y https://github.com/apache/apisix/releases/download/2.6/apisix-2.6-0.x86_64.rpm
   ```

   - تحقق من إصدار أبيسكس:

     ```shell
     $ apisix version
     ```

   - بدء أبيسكس:

     ```shell
     $ apisix start
     ```

**ملاحظة**: لن يدعم أباتشي أبيسكس بروتوكول v2 الخاص بـ etcd بعد الآن منذ APISIX v2.0 ، والحد الأدنى لإصدار etcd المدعوم هو v3.4.0. يرجى تحديث الخ عند الحاجة. إذا كنت بحاجة إلى ترحيل بياناتك من etcd v2 إلى v3 ،  يرجى متابعة [etcd ترحيل دليل](https://etcd.io/docs/v3.4.0/op-guide/v2-migration/).

### للمطورين

1. للمطورين، يمكنك استخدام أحدث فرع رئيسي لتجربة المزيد من الميزات

   - بناء من شفرة المصدر

   ```shell
   $ git clone git@github.com:apache/apisix.git
   $ cd apisix
   $ make deps
   ```

   - صورة عامل ميناء

   ```shell
   $ git clone https://github.com/apache/apisix-docker.git
   $ cd apisix-docker
   $ sudo docker build -f alpine-dev/Dockerfile .
   ```

2. البدء

   يعد دليل البدء طريقة رائعة لتعلم أساسيات أبيسكس. ما عليك سوى اتباع الخطوات الواردة في  [البدء](docs/en/latest/getting-started.md).

   Further, you can follow the documentation to try more [plugins](../en/latest/plugins).

3. مدير API

   يوفر أباتشي أبيسكس  [REST Admin API](docs/en/latest/admin-api.md) للتحكم الديناميكي في مجموعة أباتشي أبيسكس.

4. تطوير البرنامج المساعد

   يمكنك الرجوع إلى  [دليل تطوير البرنامج المساعد](docs/en/latest/plugin-develop.md), و [عينة من وثائق`echo`](docs/en/latest/plugins/echo.md) صدى البرنامج المساعد وتنفيذ التعليمات البرمجية.

   يرجى ملاحظة أن إضافات أباتشي أبيسكس المضافة ، المحدثة ، المحذوفة ، وما إلى ذلك ، يتم تحميلها دون إعادة تشغيل الخدمة.

لمزيد من الوثائق , يرجى الرجوع الى [أباتشي أبيسكس فهرس المستند](README.md)

## المعيار

باستخدام خادم AWS ثماني النواة ، تصل خدمة QPS الخاصة بـ APISIX إلى 140000 مع زمن انتقال يبلغ 0.2 مللي ثانية فقط.

[البرنامج النصي المعياري](benchmark/run.sh), [طريقة الاختبار وعملية](https://gist.github.com/membphis/137db97a4bf64d3653aa42f3e016bd01) كان مفتوح المصدر, ومرحبًا بكم في المحاولة والمساهمة.

## أباتشي أبيسكس مقابل كونغ

#### تمت تغطية كلاهما بالميزات الأساسية لبوابة API

| **سمات**         | **أباتشي أبيسكس** | **كونغ** |
| :------------------- | :---------------- | :------- |
| **المنبع الديناميكي** | نعم               | نعم      |
| **راوتر ديناميكي**   | نعم               | نعم      |
| **الفحص الصحي**     | نعم               | نعم      |
| **ديناميكي SSL**      | نعم               | نعم      |
| **L4 and L7 وكيل**  | نعم               | نعم      |
| **أبنتراكينج**      | نعم               | نعم      |
| **البرنامج المساعد المخصص**    | نعم               | نعم      |
| **REST API**         | نعم               | نعم      |
| **CLI**              | نعم               | نعم      |

#### مميزات أباتشي أبيسكس

| **سمات**                                                    | **أباتشي أبيسكس**                                 | **كونغ**                |
| :-------------------------------------------------------------- | :------------------------------------------------ | :---------------------- |
| ينتمي إلى                                                      | مؤسسة البرمجيات أباتشي                        | شركة كونغ.               |
| تكنولوجيا البناء                                               | Nginx + etcd                                      | Nginx + Postgres        |
| قنوات الاتصال                                          | لائحة الرسائل الالكترونية, مجموعة وي شات, QQ مجموعة, [جيت هاب](https://github.com/apache/apisix/issues), [Slack](https://join.slack.com/t/the-asf/shared_invite/zt-nggtva4i-hDCsW1S35MuZ2g_2DgVDGg), meetup | GitHub, Freenode, forum |
| وحدة المعالجة المركزية أحادية النواة، QPS (تمكين حد العد والإضافات بروميثيوس) | 18000                                             | 1700                    |
| وقت الاستجابة                                                         | 0.2 ms                                            | 2 ms                    |
| ديوبو                                                           | نعم                                               | لا                      |
| التراجع عن التكوين                                         | نعم                                               | لا                      |
| المسار مع TTL                                                  | نعم                                               | لا                      |
| المكونات في التحميل الساخن                                             | نعم                                               | لا                      |
| مخصص LB والمسار                                             | نعم                                               | لا                      |
| REST API <--> gRPC تحويل ترميز                                   | نعم                                               | لا                      |
| Tengine                                                         | نعم                                               | لا                      |
| MQTT                                                            | نعم                                               | لا                      |
| وقت فعالية التكوين الذي يحركه الحدث                                   | Event-driven, < 1ms                               | polling, 5 seconds      |
| لوحة القيادة                                                       | نعم                                               | لا                      |
| IdP                                                             | نعم                                               | لا                      |
| مركز التكوين HA                                         | نعم                                               | لا                      |
| حد السرعة لفترة زمنية محددة                         | نعم                                               | لا                      |
| دعم أي متغير Nginx كشرط توجيه                 | نعم                                               | لا                      |

اختبار المقارنة المعيارية [بيانات تفاصيل](https://gist.github.com/membphis/137db97a4bf64d3653aa42f3e016bd01)

### مساهم بمرور الوقت

> [قم بزيارة هنا](https://www.apiseven.com/contributor-graph) لإنشاء "مساهم بمرور الوقت".

[![مساهم-بمرور-الوقت](docs/assets/images/contributor-over-time.png)](https://www.apiseven.com/contributor-graph)

## مقاطع الفيديو والمقالات

- [أباتشي أبيسكس: كيفية تنفيذ تزامن البرنامج المساعد في بوابة API](https://www.youtube.com/watch?v=iEegNXOtEhQ)
- [تحسين إمكانية ملاحظة أباتشي أبيسكس باستخدام أباتشي سكايووكنغ](https://www.youtube.com/watch?v=DleVJwPs4i4)
- [اختيار تكنولوجيا أبيسكس والاختبار والتكامل المستمر](https://medium.com/@ming_wen/apache-apisixs-technology-selection-testing-and-continuous-integration-313221b02542)
- [تحليل الأداء الممتاز لبوابة أباتشي أبيسكس بوابة الخدمات المصغرة](https://medium.com/@ming_wen/analysis-of-excellent-performance-of-apache-apisix-microservices-gateway-fc77db4090b5)

## قصص المستخدم

- [منصة المصنع الأوروبي: API بوابة أمان – بوابة أمان API - باستخدام أبيسكس في منصة أي فاكتوري](https://www.efactory-project.eu/post/api-security-gateway-using-apisix-in-the-efactory-platform)
- [ke.com: كيفية إنشاء بوابة استنادًا إلى أباتشي أبيسكس (صيني)](https://mp.weixin.qq.com/s/yZl9MWPyF1-gOyCp8plflA)
- [360: ممارسة أباتشي أبيسكس في منصة OPS(صيني)](https://mp.weixin.qq.com/s/zHF_vlMaPOSoiNvqw60tVw)
- [هلوتوك: استكشاف العولمة على أساس OpenResty و أباتشي أبيسكس(صيني)](https://www.upyun.com/opentalk/447.html)
- [سحابة تينسنت:لماذا تختار أباتشي أبيسكس لتنفيذ وحدة تحكم الدخول k8s؟  (صيني)](https://www.upyun.com/opentalk/448.html)
- [aispeech:لماذا نقوم بإنشاء وحدة تحكم دخول k8s جديدة؟  (صيني)](https://mp.weixin.qq.com/s/bmm2ibk2V7-XYneLo9XAPQ)

## من يستخدم أبيسكس?

تستخدم مجموعة متنوعة من الشركات والمؤسسات أبيسكس للبحث والإنتاج والمنتجات التجارية ، بما في ذلك:

<img src="https://user-images.githubusercontent.com/40708551/109484046-f7c4e280-7aa5-11eb-9d71-aab90830773a.png" width="725" height="1700" />

يتم تشجيع المستخدمين على إضافة أنفسهم إلى صفحة  [Powered By](powered-by.md) صفحة.

## الشاشة العريضة

<p align="left">
<img src="https://landscape.cncf.io/images/left-logo.svg" width="150">&nbsp;&nbsp;<img src="https://landscape.cncf.io/images/right-logo.svg" width="200" />
<br /><br />
يثري أبيسكس . <a href="https://landscape.cncf.io/card-mode?category=api-gateway&grouping=category">
CNCF API مشهد بوابةe.</a>
</p>

## شعارات

- [شعار أباتشي ابيسكس(PNG)](https://github.com/apache/apisix/tree/master/logos/apache-apisix.png)
- [شعار أباتشي ابيسكس مصدر](https://apache.org/logos/#apisix)

## شكر و تقدير

مستوحى من كونغ و اروانج.

## رخصة

[أباتشي 2.0 رخصة](https://github.com/apache/apisix/tree/master/LICENSE)

</div>
