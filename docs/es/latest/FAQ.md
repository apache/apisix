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

# PREGUNTAS FRECUENTES

## ¿Por qué un nuevo portal API?

Existen nuevos requerimientos para los portales API en el campo de los microservicios: mayor flexibilidad, requerimientos de desempeño más elevados y origen (native) en la nube.

## ¿Cuáles son las diferencias entre APISIX y otros portales API?

APISIX está basado en etcd para guardar y sincronizar la configuración, no en bases de datos relacionales tales como Postgres o MySQL.

Esto no solamente elimina el recabado de información (polling) y hace el código más conciso, sino también hace que la sincronización de la configuración se haga más en tiempo real. Al mismo tiempo, no habrá un punto único en el sistema, lo que resulta más útil.

Adicionalmente, APISIX tiene un enrutado dinámico y carga en caliente de los plug-ins, lo que es especialmente aplicable al manejo de API bajo sistemas de micro-servicios.

## ¿Cómo es el desempeño de APISIX?

Uno de los objetivos del diseño y desarrollo de APISIX es lograr el más elevado desempeño en la industria. Datos de las pruebas específicas pueden consultarse aquí：[banco de pruebas - benchmark](../../en/latest/benchmark.md)

APISIX es el portal API de mayor desempeño; con un QPS de un solo núcleo logra 23,000, con un retardo promedio de solamente 0.6 milisegundos.

## ¿Tiene APISIX un interfase de cónsola?

Sí, en la versión 0.6 contamos con un tablero incorporado, y usted puede operar APISIX a través de la interfase web.

## ¿Puedo escribir mi propio plugin?

Por supuesto, APISIX provee plugins personalizados y flexibles para que los desarrolladores y las empresas escriban sus propios programas.

[Cómo escribir un plug-in](../../en/latest/plugin-develop.md)

## ¿Por qué elegimos etcd como el centro de la configuración?

Para el centro de la configuración, la configuración del almacenamiento es solamente la función más básica, y APISIX necesita también las siguientes prestaciones:

1. Grupos (Cluster)
2. Transacciones
3. Control de concurrencia multi-versión
4. Notificación de cambios
5. Alto rendimiento

Más información en [Por qué etcd](https://github.com/etcd-io/website/blob/master/content/docs/next/learning/why.md#comparison-chart).

## ¿Por qué sucede que instalar dependencias APISIX con Luarocks provoca interrupciones por exceso de tiempo (timeout), o instalaciones lentas y fallidas?

Existen dos posibilidades cuando encontramos Luarocks muy lentos:

1. El servidor usado para instalar Luarocks está bloqueado
2. En algún punto entre su red y el servidor de github se bloquea el protocolo 'git'

Para el primer problema usted puede usar https_proxy o usar la opción `--server` para especificar un servidor de Luarocks al que usted pueda acceder con mayor velocidad.
Ejecute el comando `luarocks config rocks_servers` (este comando es soportado por versiones posteriores a luarocks 3.0) para ver qué servidores están disponibles.

Si usar un proxy no resuelve este problema, usted puede agregar la opción `--verbose` durante la instalación para ver qué tan lento está. Excluyendo el primer caso, solamente en el segundo, cuando el protocolo `git` está bloqueado, podemos ejecutar `git config --global url."https://".insteadOf git://` para usar el protocolo 'HTTPS' en lugar de `git`.

## ¿Cómo se soporta un lanzamiento en etapa "gray release" (lanzamiento gris) a través de APISIX?

Un ejemplo, `foo.com/product/index.html?id=204&page=2`, lanzamiento gris (gray release) basado en `id` en la cadena de consulta (query string) en URL como una condición：

1. Grupo A：id <= 1000
2. Grupo B：id > 1000

Hay dos formas diferentes de hacer esto：

1. Usar el campo `vars` de la ruta para hacerlo.

```shell
curl -i http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "vars": [
        ["arg_id", "<=", "1000"]
    ],
    "plugins": {
        "redirect": {
            "uri": "/test?group_id=1"
        }
    }
}'

curl -i http://127.0.0.1:9080/apisix/admin/routes/2 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "vars": [
        ["arg_id", ">", "1000"]
    ],
    "plugins": {
        "redirect": {
            "uri": "/test?group_id=2"
        }
    }
}'
```

Aquí encontramos la lista de operadores del `lua-resty-radixtree` actual：
https://github.com/iresty/lua-resty-radixtree#operator-list

2. Usar el plug-in `traffic-split` para hacerlo.

Por favor consultar la documentación de plug-in [traffic-split.md](../../en/latest/plugins/traffic-split.md) para ver ejemplos de uso.

## ¿Cómo redireccionar http a https usando APISIX?

Por ejemplo, redireccionar `http://foo.com` a `https://foo.com`

Hay varias maneras de hacerlo.

1. Directamente usando el plug-in `http_to_https` en `redirect`：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hello",
    "host": "foo.com",
    "plugins": {
        "redirect": {
            "http_to_https": true
        }
    }
}'
```

2. Usando la regla avanzada de enrutamiento `vars` con el plug-in `redirect`:

```shell
curl -i http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hello",
    "host": "foo.com",
    "vars": [
        [
            "scheme",
            "==",
            "http"
        ]
    ],
    "plugins": {
        "redirect": {
            "uri": "https://$host$request_uri",
            "ret_code": 301
        }
    }
}'
```

3. Con el plug-in `serverless`：

```shell
curl -i http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hello",
    "plugins": {
        "serverless-pre-function": {
            "phase": "rewrite",
            "functions": ["return function() if ngx.var.scheme == \"http\" and ngx.var.host == \"foo.com\" then ngx.header[\"Location\"] = \"https://foo.com\" .. ngx.var.request_uri; ngx.exit(ngx.HTTP_MOVED_PERMANENTLY); end; end"]
        }
    }
}'
```

Luego hacemos una prueba para ver si funciona：

```shell
curl -i -H 'Host: foo.com' http://127.0.0.1:9080/hello
```

La respuesta debería ser:

```
HTTP/1.1 301 Moved Permanently
Date: Mon, 18 May 2020 02:56:04 GMT
Content-Type: text/html
Content-Length: 166
Connection: keep-alive
Location: https://foo.com/hello
Server: APISIX web server

<html>
<head><title>301 Moved Permanently</title></head>
<body>
<center><h1>301 Moved Permanently</h1></center>
<hr><center>openresty</center>
</body>
</html>
```

## Cómo arreglar un fallo de instalación de OpenResty en MacOS 10.15

Cuando usted instala OpenResty en MacOs 10.15, usted puede encontrarse con este error

```shell
> brew install openresty
Updating Homebrew...
==> Auto-updated Homebrew!
Updated 1 tap (homebrew/cask).
No changes to formulae.

==> Installing openresty from openresty/brew
Warning: A newer Command Line Tools release is available.
Update them from Software Update in System Preferences or
https://developer.apple.com/download/more/.

==> Downloading https://openresty.org/download/openresty-1.15.8.2.tar.gz
Already downloaded: /Users/wusheng/Library/Caches/Homebrew/downloads/4395089f0fd423261d4f1124b7beb0f69e1121e59d399e89eaa6e25b641333bc--openresty-1.15.8.2.tar.gz
==> ./configure -j8 --prefix=/usr/local/Cellar/openresty/1.15.8.2 --pid-path=/usr/local/var/run/openresty.pid --lock-path=/usr/
Last 15 lines from /Users/wusheng/Library/Logs/Homebrew/openresty/01.configure:
DYNASM    host/buildvm_arch.h
HOSTCC    host/buildvm.o
HOSTLINK  host/buildvm
BUILDVM   lj_vm.S
BUILDVM   lj_ffdef.h
BUILDVM   lj_bcdef.h
BUILDVM   lj_folddef.h
BUILDVM   lj_recdef.h
BUILDVM   lj_libdef.h
BUILDVM   jit/vmdef.lua
make[1]: *** [lj_folddef.h] Segmentation fault: 11
make[1]: *** Deleting file `lj_folddef.h'
make[1]: *** Waiting for unfinished jobs....
make: *** [default] Error 2
ERROR: failed to run command: gmake -j8 TARGET_STRIP=@: CCDEBUG=-g XCFLAGS='-msse4.2 -DLUAJIT_NUMMODE=2 -DLUAJIT_ENABLE_LUA52COMPAT' CC=cc PREFIX=/usr/local/Cellar/openresty/1.15.8.2/luajit

If reporting this issue please do so at (not Homebrew/brew or Homebrew/core):
  https://github.com/openresty/homebrew-brew/issues

These open issues may also help:
Can't install openresty on macOS 10.15 https://github.com/openresty/homebrew-brew/issues/10
The openresty-debug package should use openresty-openssl-debug instead https://github.com/openresty/homebrew-brew/issues/3
Fails to install OpenResty https://github.com/openresty/homebrew-brew/issues/5

Error: A newer Command Line Tools release is available.
Update them from Software Update in System Preferences or
https://developer.apple.com/download/more/.
```

Este es un problema de OS incompatible, y puede superarse con estos dos pasos

1. `brew edit openresty/brew/openresty`
2. Agregar `\ -fno-stack-check` en la línea con with-luajit-xcflags.

## ¿Cómo cambiar el nivel de log?

El nivel de log por defecto para APISIX es `warn`. Sin embargo, usted puede cambiar el nivel de log a `info` si usted quiere rastrear los mensajes mostrados en `core.log.info`.

Pasos:

1. Modificar el parámetro `error_log_level: "warn"` a `error_log_level: "info"` en conf/config.yaml

2. Recargar y reiniciar APISIX

Ahora usted podrá rastrear y examinar el log del nivel info en logs/error.log.

## ¿Cómo recargar su propio plug-in?

El plug-in The Apache APISIX soporta recargas en caliente.
Ver la sección `Hot reload` en [plugins](../../en/latest/plugins.md) para tener información acerca de cómo hacerlo.

## ¿Cómo lograr que APISIX atienda múltiples puertos cuando esté manejando solicitudes (requests) HTTP o HTTPS?

Por defecto, APISIX atiende solamente el puerto 9080 cuando maneja solicitudes HTTP. Si usted desea que APISIX atienda solicitudes de múltiples puertos, Ud. deberá modificar los parámetros relevantes del archivo de configuración como se muestra a continuación:

1. Modificar el parámetro de puertos atendidos de HTTP, `node_listen` en `conf/config.yaml`, por ejemplo:

   ```
    apisix:
      node_listen:
        - 9080
        - 9081
        - 9082
   ```

   El manejo de las solicitudes HTTPS es similar, modificando el parámetro de puertos atendidos de HTTPS, `ssl.listen_port` en `conf/config.yaml`, por ejemplo:

    ```
    apisix:
      ssl:
        listen_port:
          - 9443
          - 9444
          - 9445
    ```

2. Recargar y reiniciar APISIX

## ¿Cómo usa APISIX a etcd para lograr una sincronización de configuración en un nivel de milisegundos?

etcd provee funciones de subscripción para monitorear si la palabra clave específica o si el directorio sufren algún cambio (por ejemplo: [watch](https://github.com/api7/lua-resty-etcd/blob/master/api_v3.md#watch), [watchdir](https://github.com/api7/lua-resty-etcd/blob/master/api_v3.md#watchdir)).

APISIX usa [etcd.watchdir](https://github.com/api7/lua-resty-etcd/blob/master/api_v3.md#watchdir) para monitorear cambios en el contenido del directorio:

* Si no hay ninguna actualización en los datos del directorio monitoreado: el proceso será bloqueado hasta que termine el tiempo (timeout) o hasta que ocurran otros errores.
* Si el directorio monitoreado sufre una actualización en sus datos: etcd retornará los nuevos datos suscritos inmediatamente (en milisegundos), y APISIX lo actualizará en la memoria caché.

Con la ayuda de etcd, cuyas prestaciones de notificación incremental son del nivel de milisegundos, APISIX alcanza este mismo nivel de milisegundos en la sincronización de la configuración.

## ¿Cómo personalizar la id de instancia en APISIX?

Por defecto, APISIX leerá la id de instancia en `conf/apisix.uid`. Si no se encuentra, y ninguna id está configurada, APISIX generará una `uuid` como la id de instancia.

Si usted desea especificar una id de su preferencia para asegurar la instancia de APISIX a su sistema interno, podrá configurarla en `conf/config.yaml`, por ejemplo:

    ```
    apisix:
      id: "your-meaningful-id"
    ```

## ¿Por qué aparece con frecuencia el error "failed to fetch data from etcd, failed to read etcd dir, etcd key: xxxxxx" (no se pudieron leer los datos de etcd, no se pudo leer el dir de etcd, etcd key: xxxxxx) en el archivo error.log?

En primer lugar asegúrese de que la red entre APISIX y el cluster de etcd no está particionada.

Si la red está en buenas condiciones, por favor revise que su cluster de etcd tenga activado el portal [gRPC gateway](https://etcd.io/docs/v3.4.0/dev-guide/api_grpc_gateway/). Sin embargo, el caso por defecto para esta característica es diferente cuando se usan las opciones de la línea de comandos que cuando se usa el archivo de configuración para iniciar el servidor etcd.

1. Cuando se usan las opciones de la línea de comandos, esta característica es activada por defecto, la opción pertinente es `--enable-grpc-gateway`.

```sh
etcd --enable-grpc-gateway --data-dir=/path/to/data
```

Nótese que esta opción no se muestra en la salida de `etcd --help`.

2. Cuando se usa el archivo de configuración, esta característica está desactivada por defecto, por favor actívela usando `enable-grpc-gateway` de manera explícita.

```json
# etcd.json
{
    "enable-grpc-gateway": true,
    "data-dir": "/path/to/data"
}
```

Esta distinción fue eliminada por etcd en su ramal principal (master branch), pero no se trasladó la modificación a las versiones anunciadas, así que sea prudente al desplegar su cluster de etcd.

## ¿Cómo lograr clusters Apache APISIX con disponibilidad elevada?

La elevada disponibilidad de APISIX puede dividirse en dos partes:

1. El plano de datos de Apache APISIX carece de estados y su escala se puede cambiar elásticamente a voluntad. Basta añadir una capa (layer) de LB en el frente.

2. El plano de datos de Apache APISIX tiene su base en la implementación de alta disponibilidad de `etcd cluster` y no requiere ninguna dependencia de base de datos relacional.
