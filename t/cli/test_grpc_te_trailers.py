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

import json
import os
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import grpc
from google.protobuf.wrappers_pb2 import StringValue


def say_hello(request, _context):
    return StringValue(value=f"Hello {request.value}")


def check_response(nginx):
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    url = "http://127.0.0.1:19280/grpc-te?name=APISIX"
    deadline = time.monotonic() + 10
    while nginx.poll() is None and time.monotonic() < deadline:
        try:
            with opener.open(url, timeout=5) as response:
                assert response.status == 200, response.status
                body = json.load(response)
        except urllib.error.HTTPError as error:
            grpc_message = error.headers.get("grpc-message")
            raise AssertionError(
                f"Expected a successful gRPC response, got HTTP {error.code}: "
                f"{grpc_message or error.read().decode(errors='replace')}"
            ) from error
        except urllib.error.URLError as error:
            if not isinstance(error.reason, ConnectionRefusedError):
                raise
            time.sleep(0.1)
        else:
            assert body == {"message": "Hello APISIX"}, body
            return
    raise AssertionError("APISIX did not start")


def run_test(root, upstream_port):
    with tempfile.TemporaryDirectory(prefix="apisix-grpc-te-") as directory:
        prefix = Path(directory)
        # The Nginx worker must be able to read the standalone configuration.
        prefix.chmod(0o755)
        for name in ("apisix", "deps"):
            target = root / name
            if target.exists():
                (prefix / name).symlink_to(target, target_is_directory=True)
        (prefix / "logs").mkdir()
        conf = prefix / "conf"
        conf.mkdir()
        (conf / "mime.types").symlink_to(root / "conf/mime.types")
        (conf / "config.yaml").write_text(
            """apisix:
  node_listen:
    - ip: 127.0.0.1
      port: 19280
  enable_control: false
  ssl:
    enable: false
plugins:
  - grpc-transcode
stream_plugins: []
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
nginx_config:
  worker_processes: 1
""",
            encoding="utf-8",
        )
        (conf / "apisix.yaml").write_text(
            f"""protos:
  - id: hello
    content: |
      syntax = "proto3";
      package helloworld;
      message HelloRequest {{ string name = 1; }}
      message HelloReply {{ string message = 1; }}
      service Greeter {{
        rpc SayHello (HelloRequest) returns (HelloReply);
      }}
routes:
  - id: grpc-te
    uri: /grpc-te
    plugins:
      grpc-transcode:
        proto_id: hello
        service: helloworld.Greeter
        method: SayHello
    upstream:
      type: roundrobin
      scheme: grpc
      nodes:
        "127.0.0.1:{upstream_port}": 1
#END
""",
            encoding="utf-8",
        )

        env = os.environ.copy()
        env.pop("APISIX_PROFILE", None)
        subprocess.run([root / "bin/apisix", "init"], cwd=prefix, env=env, check=True)
        with subprocess.Popen(
            ["openresty", "-p", prefix, "-c", conf / "nginx.conf", "-g", "daemon off;"],
            env=env,
        ) as nginx:
            try:
                check_response(nginx)
            except Exception:
                error_log = prefix / "logs/error.log"
                if error_log.is_file():
                    print(error_log.read_text(encoding="utf-8", errors="replace"), end="")
                raise
            finally:
                if nginx.poll() is None:
                    nginx.terminate()
                    try:
                        nginx.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        nginx.kill()


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[2]
    with ThreadPoolExecutor(max_workers=1) as executor:
        server = grpc.server(executor)
        # The request and response each have a single string at protobuf field 1.
        handler = grpc.unary_unary_rpc_method_handler(
            say_hello,
            request_deserializer=StringValue.FromString,
            response_serializer=StringValue.SerializeToString,
        )
        server.add_generic_rpc_handlers(
            (grpc.method_handlers_generic_handler("helloworld.Greeter", {"SayHello": handler}),)
        )
        port = server.add_insecure_port("127.0.0.1:0")
        server.start()
        try:
            run_test(root, port)
        finally:
            server.stop(0).wait()
    print("passed: grpc-transcode reached a Python gRPC server with TE: trailers")
