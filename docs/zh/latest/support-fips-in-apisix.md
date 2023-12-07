---
id: support-fips-in-apisix
title: 通过 OpenSSL 3.0 使 APISIX 支持 FIPS 模式
keywords:
  - API 网关
  - Apache APISIX
  - 贡献代码
  - 构建 APISIX
  - OpenSSL 3.0 FIPS
description: 本文将介绍如何在 Apache APISIX 中使用 OpenSSL 3.0 来编译 apisix-runtime，即可启用 FIPS 模式。
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

目前，OpenSSL 3.0 [支持了](https://www.openssl.org/blog/blog/2022/08/24/FIPS-validation-certificate-issued/) [FIPS](https://en.wikipedia.org/wiki/FIPS_140-2) 模式。为了在 APISIX 中支持 FIPS 模式，你应该使用 OpenSSL 3.0 来编译 apisix-runtime。

## 编译

如果你需要使用 OpenSSL 3.0 来编译 apisix-runtime，请以 root 用户角色来执行以下命令：

```bash
cd $(mktemp -d)
OPENSSL3_PREFIX=${OPENSSL3_PREFIX-/usr/local}
apt install -y build-essential
git clone https://github.com/openssl/openssl
cd openssl
./Configure --prefix=$OPENSSL3_PREFIX/openssl-3.0 enable-fips
make install
echo $OPENSSL3_PREFIX/openssl-3.0/lib64 > /etc/ld.so.conf.d/openssl3.conf
ldconfig
$OPENSSL3_PREFIX/openssl-3.0/bin/openssl fipsinstall -out $OPENSSL3_PREFIX/openssl-3.0/ssl/fipsmodule.cnf -module $OPENSSL3_PREFIX/openssl-3.0/lib64/ossl-modules/fips.so
sed -i 's@# .include fipsmodule.cnf@.include '"$OPENSSL3_PREFIX"'/openssl-3.0/ssl/fipsmodule.cnf@g; s/# \(fips = fips_sect\)/\1\nbase = base_sect\n\n[base_sect]\nactivate=1\n/g' $OPENSSL3_PREFIX/openssl-3.0/ssl/openssl.cnf
cd ..

export cc_opt="-I$OPENSSL3_PREFIX/openssl-3.0/include"
export ld_opt="-L$OPENSSL3_PREFIX/openssl-3.0/lib64 -Wl,-rpath,$OPENSSL3_PREFIX/openssl-3.0/lib64"

wget --no-check-certificate https://raw.githubusercontent.com/api7/apisix-build-tools/master/build-apisix-runtime.sh
chmod +x build-apisix-runtime.sh
./build-apisix-runtime.sh
```

apisix-runtime 将安装在 `/usr/local/openresty`。
