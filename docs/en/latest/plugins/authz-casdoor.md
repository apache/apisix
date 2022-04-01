---
title: authz-casdoor
---

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

## Description

`authz-casdoor` is an authorization plugin based on [Casdoor](https://casdoor.org/). Casdoor is a centralized authentication / Single-Sign-On (SSO) platform supporting OAuth 2.0, OIDC and SAML, integrated with Casbin RBAC and ABAC permission management.

## Attributes

| Name        | Type   | Requirement | Default | Valid | Description                                                  |
| ----------- | ------ | ----------- | ------- | ----- | ------------------------------------------------------------ |
| endpoint_addr  | string | required    |         |       | The url of casdoor.             |
| client_id | string | required    |         |       | The client id in casdoor.                          |
| client_secret       | string | required    |         |       | The client secret in casdoor.               |
| callback_url      | string | required    |         |       | The callback url which is used to receive state and code.                            |

*Note: endpoint_addr and callback_url should not end with '/'*

## How To Enable

You can enable the plugin on any route by giving out all attributes mentioned above.

### Example

```shell
curl "http://127.0.0.1:9080/apisix/admin/routes/1" -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d '
{
  "methods": ["GET"],
  "uri": "/anything/*",
  "plugins": {
    "authz-casdoor": {
        "endpoint_addr":"http://localhost:8000",
        "callback_url":"http://localhost:9080/anything/callback",
        "client_id":"7ceb9b7fda4a9061ec1c",
        "client_secret":"3416238e1edf915eac08b8fe345b2b95cdba7e04"
    }
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:80": 1
    }
  }
}'

```

In this example, using apisix's admin API we created a route "/anything/*" pointed to "httpbin.org:80", and with "authz-casdoor" enabled. This route is now under authentication protection of Casdoor.

#### Explanations about parameters of this plugin

In the configuration of "authz-casdoor" plugin we can see four parameters.

The first one is "callback_url". This is exactly the callback url in OAuth2. It should be emphasized that this callback url **must belong to the "uri" you specified for the route**, for example, in this example, http://localhost:9080/anything/callback obviously belong to "/anything/*". Only by this way can the visit toward callback_url can be intercepted and utilized by the plugin(so that the plugin can get the code and state in Oauth2). The logic of callback_url is implemented completely by the plugin so that there is no need to modify the server to implement this callback.

The second parameter "endpoint_addr" is obviously the url of Casdoor. The third and fourth parameters are "client_id" and "client_secret", which you can acquire from Casdoor when you register an app.

#### How it works?

Suppose a new user who has never visited this route before is going to visit it (http://localhost:9080/anything/d?param1=foo&param2=bar), considering that "authz-casdoor" is enabled, this visit would be processed by "authz-casdoor" plugin first. After checking the session and confirming that this user hasn't been authenticated, the visit will be intercepted. With the original url user wants to visit kept, he will be redirected to the login page of Casdoor.

After successfully logging in with username and password(or whatever method he uses), Casdoor will redirect this user to the "callback_url" with GET parameter "code" and "state" specified. Because the "callback_url" is known by the plugin, when the visit toward the "callback_url" is intercepted this time, the logic of "Authorization code Grant Flow" in Oauth2 will be triggered, which means this plugin will request the access token to confirm whether this user is really logged in. After this confirmation, this plugin will redirect this user to the original url user wants to visit, which was kept by us previously. The logged-in status will also be kept in the session.

Next time this user want to visit url behind this route (for example, http://localhost:9080/anything/d), after discovering that this user has been authenticated previously, this plugin won't redirect this user anymore so that this user can visit whatever he wants under this route without being interfered.
