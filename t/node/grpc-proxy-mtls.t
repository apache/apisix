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
use t::APISIX;

my $nginx_binary = $ENV{'TEST_NGINX_BINARY'} || 'nginx';
my $version = eval { `$nginx_binary -V 2>&1` };

if ($version !~ m/\/apisix-nginx-module/) {
    plan(skip_all => "apisix-nginx-module not installed");
} else {
    plan('no_plan');
}

no_long_string();
no_root_location();
no_shuffle();
add_block_preprocessor(sub {
    my ($block) = @_;
    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: Unary API grpcs proxy test with mTLS
--- http2
--- apisix_yaml
routes:
  -
    id: 1
    uris:
        - /helloworld.Greeter/SayHello
    methods: [
        POST
    ]
    upstream:
      scheme: grpcs
      tls:
        client_cert: "-----BEGIN CERTIFICATE-----\nMIIDOjCCAiICAwD6zzANBgkqhkiG9w0BAQsFADBnMQswCQYDVQQGEwJjbjESMBAG\nA1UECAwJR3VhbmdEb25nMQ8wDQYDVQQHDAZaaHVIYWkxDTALBgNVBAoMBGFwaTcx\nDDAKBgNVBAsMA29wczEWMBQGA1UEAwwNY2EuYXBpc2l4LmRldjAeFw0yMDA2MjAx\nMzE1MDBaFw0zMDA3MDgxMzE1MDBaMF0xCzAJBgNVBAYTAmNuMRIwEAYDVQQIDAlH\ndWFuZ0RvbmcxDTALBgNVBAoMBGFwaTcxDzANBgNVBAcMBlpodUhhaTEaMBgGA1UE\nAwwRY2xpZW50LmFwaXNpeC5kZXYwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEK\nAoIBAQCfKI8uiEH/ifZikSnRa3/E2B4ohVWRwjo/IxyDEWomgR4tLk1pSJhP/4SC\nLWuMQTFWTbSqt1IFYy4ZbVSHHyGoNPmJGrHRJCGE+sgpfzn0GjV4lXQPJD0k6GR1\nCX2Mo1TWdFqSJ/Hc5AQwcQFnPfoLAwsBy4yqrlmf96ZAUytl/7Zkjf4P7mJkJHtM\n/WgSR0pGhjZTAGRf5DJWoO51ki3i3JI+15mOhmnnCpnksnGVPfl92q92Hz/4v3iq\nE+UThPYRpcGbnddzMvPaCXiavg8B/u2LVbn4l0adamqQGepOAjD/1xraOVP2W22W\n0PztDXJ4rLe+capNS4oGuSUfkIENAgMBAAEwDQYJKoZIhvcNAQELBQADggEBAHKn\nHxUhuk/nL2Sg5UB84OoJe5XPgNBvVMKN0c/NAPKVIPninvUcG/mHeKexPzE0sMga\nRNos75N2199EXydqUcsJ8jL0cNtQ2k5JQXXg0ntNC4tuCgIKAOnO879y5hSG36e5\n7wmAoVKnabgjej09zG1kkXvAmpgqoxeVCu7h7fK+AurLbsGCTaHoA5pG1tcHDxJQ\nfpVcbBfwQDSBW3SQjiRqX453/01nw6kbOeLKYraJysaG8ZU2K8+WpW6JDubciHjw\nfQnpU2U16XKivhxeuKYrV/INL0sxj/fZraNYErvJWzh5llvIdNLmeSPmvb50JUIs\n+lDqn1MobTXzDpuCFXA=\n-----END CERTIFICATE-----\n",
        client_key: "-----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKCAQEAnyiPLohB/4n2YpEp0Wt/xNgeKIVVkcI6PyMcgxFqJoEeLS5N\naUiYT/+Egi1rjEExVk20qrdSBWMuGW1Uhx8hqDT5iRqx0SQhhPrIKX859Bo1eJV0\nDyQ9JOhkdQl9jKNU1nRakifx3OQEMHEBZz36CwMLAcuMqq5Zn/emQFMrZf+2ZI3+\nD+5iZCR7TP1oEkdKRoY2UwBkX+QyVqDudZIt4tySPteZjoZp5wqZ5LJxlT35fdqv\ndh8/+L94qhPlE4T2EaXBm53XczLz2gl4mr4PAf7ti1W5+JdGnWpqkBnqTgIw/9ca\n2jlT9lttltD87Q1yeKy3vnGqTUuKBrklH5CBDQIDAQABAoIBAHDe5bPdQ9jCcW3z\nfpGax/DER5b6//UvpfkSoGy/E+Wcmdb2yEVLC2FoVwOuzF+Z+DA5SU/sVAmoDZBQ\nvapZxJeygejeeo5ULkVNSFhNdr8LOzJ54uW+EHK1MFDj2xq61jaEK5sNIvRA7Eui\nSJl8FXBrxwmN3gNJRBwzF770fImHUfZt0YU3rWKw5Qin7QnlUzW2KPUltnSEq/xB\nkIzyWpuj7iAm9wTjH9Vy06sWCmxj1lzTTXlanjPb1jOTaOhbQMpyaAzRgQN8PZiE\nYKCarzVj7BJr7/vZYpnQtQDY12UL5n33BEqMP0VNHVqv+ZO3bktfvlwBru5ZJ7Cf\nURLsSc0CgYEAyz7FzV7cZYgjfUFD67MIS1HtVk7SX0UiYCsrGy8zA19tkhe3XVpc\nCZSwkjzjdEk0zEwiNAtawrDlR1m2kverbhhCHqXUOHwEpujMBjeJCNUVEh3OABr8\nvf2WJ6D1IRh8FA5CYLZP7aZ41fcxAnvIPAEThemLQL3C4H5H5NG2WFsCgYEAyHhP\nonpS/Eo/OXKYFLR/mvjizRVSomz1lVVL+GWMUYQsmgsPyBJgyAOX3Pqt9catgxhM\nDbEr7EWTxth3YeVzamiJPNVK0HvCax9gQ0KkOmtbrfN54zBHOJ+ieYhsieZLMgjx\niu7Ieo6LDGV39HkvekzutZpypiCpKlMaFlCFiLcCgYEAmAgRsEj4Nh665VPvuZzH\nZIgZMAlwBgHR7/v6l7AbybcVYEXLTNJtrGEEH6/aOL8V9ogwwZuIvb/TEidCkfcf\nzg/pTcGf2My0MiJLk47xO6EgzNdso9mMG5ZYPraBBsuo7NupvWxCp7NyCiOJDqGH\nK5NmhjInjzsjTghIQRq5+qcCgYEAxnm/NjjvslL8F69p/I3cDJ2/RpaG0sMXvbrO\nVWaMryQyWGz9OfNgGIbeMu2Jj90dar6ChcfUmb8lGOi2AZl/VGmc/jqaMKFnElHl\nJ5JyMFicUzPMiG8DBH+gB71W4Iy+BBKwugHBQP2hkytewQ++PtKuP+RjADEz6vCN\n0mv0WS8CgYBnbMRP8wIOLJPRMw/iL9BdMf606X4xbmNn9HWVp2mH9D3D51kDFvls\n7y2vEaYkFv3XoYgVN9ZHDUbM/YTUozKjcAcvz0syLQb8wRwKeo+XSmo09+360r18\nzRugoE7bPl39WdGWaW3td0qf1r9z3sE2iWUTJPRQ3DYpsLOYIgyKmw==\n-----END RSA PRIVATE KEY-----\n"
      nodes:
        "127.0.0.1:50053": 1
      type: roundrobin
#END
--- exec
grpcurl -import-path ./t/grpc_server_example/proto -proto helloworld.proto -plaintext -d '{"name":"apisix"}' 127.0.0.1:1984 helloworld.Greeter.SayHello
--- response_body
{
  "message": "Hello apisix"
}



=== TEST 2: Bidirectional API grpcs proxy test with mTLS
--- http2
--- apisix_yaml
routes:
  -
    id: 1
    uris:
        - /helloworld.Greeter/SayHelloBidirectionalStream
    methods: [
        POST
    ]
    upstream:
      scheme: grpcs
      tls:
        client_cert: "-----BEGIN CERTIFICATE-----\nMIIDOjCCAiICAwD6zzANBgkqhkiG9w0BAQsFADBnMQswCQYDVQQGEwJjbjESMBAG\nA1UECAwJR3VhbmdEb25nMQ8wDQYDVQQHDAZaaHVIYWkxDTALBgNVBAoMBGFwaTcx\nDDAKBgNVBAsMA29wczEWMBQGA1UEAwwNY2EuYXBpc2l4LmRldjAeFw0yMDA2MjAx\nMzE1MDBaFw0zMDA3MDgxMzE1MDBaMF0xCzAJBgNVBAYTAmNuMRIwEAYDVQQIDAlH\ndWFuZ0RvbmcxDTALBgNVBAoMBGFwaTcxDzANBgNVBAcMBlpodUhhaTEaMBgGA1UE\nAwwRY2xpZW50LmFwaXNpeC5kZXYwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEK\nAoIBAQCfKI8uiEH/ifZikSnRa3/E2B4ohVWRwjo/IxyDEWomgR4tLk1pSJhP/4SC\nLWuMQTFWTbSqt1IFYy4ZbVSHHyGoNPmJGrHRJCGE+sgpfzn0GjV4lXQPJD0k6GR1\nCX2Mo1TWdFqSJ/Hc5AQwcQFnPfoLAwsBy4yqrlmf96ZAUytl/7Zkjf4P7mJkJHtM\n/WgSR0pGhjZTAGRf5DJWoO51ki3i3JI+15mOhmnnCpnksnGVPfl92q92Hz/4v3iq\nE+UThPYRpcGbnddzMvPaCXiavg8B/u2LVbn4l0adamqQGepOAjD/1xraOVP2W22W\n0PztDXJ4rLe+capNS4oGuSUfkIENAgMBAAEwDQYJKoZIhvcNAQELBQADggEBAHKn\nHxUhuk/nL2Sg5UB84OoJe5XPgNBvVMKN0c/NAPKVIPninvUcG/mHeKexPzE0sMga\nRNos75N2199EXydqUcsJ8jL0cNtQ2k5JQXXg0ntNC4tuCgIKAOnO879y5hSG36e5\n7wmAoVKnabgjej09zG1kkXvAmpgqoxeVCu7h7fK+AurLbsGCTaHoA5pG1tcHDxJQ\nfpVcbBfwQDSBW3SQjiRqX453/01nw6kbOeLKYraJysaG8ZU2K8+WpW6JDubciHjw\nfQnpU2U16XKivhxeuKYrV/INL0sxj/fZraNYErvJWzh5llvIdNLmeSPmvb50JUIs\n+lDqn1MobTXzDpuCFXA=\n-----END CERTIFICATE-----\n",
        client_key: "-----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKCAQEAnyiPLohB/4n2YpEp0Wt/xNgeKIVVkcI6PyMcgxFqJoEeLS5N\naUiYT/+Egi1rjEExVk20qrdSBWMuGW1Uhx8hqDT5iRqx0SQhhPrIKX859Bo1eJV0\nDyQ9JOhkdQl9jKNU1nRakifx3OQEMHEBZz36CwMLAcuMqq5Zn/emQFMrZf+2ZI3+\nD+5iZCR7TP1oEkdKRoY2UwBkX+QyVqDudZIt4tySPteZjoZp5wqZ5LJxlT35fdqv\ndh8/+L94qhPlE4T2EaXBm53XczLz2gl4mr4PAf7ti1W5+JdGnWpqkBnqTgIw/9ca\n2jlT9lttltD87Q1yeKy3vnGqTUuKBrklH5CBDQIDAQABAoIBAHDe5bPdQ9jCcW3z\nfpGax/DER5b6//UvpfkSoGy/E+Wcmdb2yEVLC2FoVwOuzF+Z+DA5SU/sVAmoDZBQ\nvapZxJeygejeeo5ULkVNSFhNdr8LOzJ54uW+EHK1MFDj2xq61jaEK5sNIvRA7Eui\nSJl8FXBrxwmN3gNJRBwzF770fImHUfZt0YU3rWKw5Qin7QnlUzW2KPUltnSEq/xB\nkIzyWpuj7iAm9wTjH9Vy06sWCmxj1lzTTXlanjPb1jOTaOhbQMpyaAzRgQN8PZiE\nYKCarzVj7BJr7/vZYpnQtQDY12UL5n33BEqMP0VNHVqv+ZO3bktfvlwBru5ZJ7Cf\nURLsSc0CgYEAyz7FzV7cZYgjfUFD67MIS1HtVk7SX0UiYCsrGy8zA19tkhe3XVpc\nCZSwkjzjdEk0zEwiNAtawrDlR1m2kverbhhCHqXUOHwEpujMBjeJCNUVEh3OABr8\nvf2WJ6D1IRh8FA5CYLZP7aZ41fcxAnvIPAEThemLQL3C4H5H5NG2WFsCgYEAyHhP\nonpS/Eo/OXKYFLR/mvjizRVSomz1lVVL+GWMUYQsmgsPyBJgyAOX3Pqt9catgxhM\nDbEr7EWTxth3YeVzamiJPNVK0HvCax9gQ0KkOmtbrfN54zBHOJ+ieYhsieZLMgjx\niu7Ieo6LDGV39HkvekzutZpypiCpKlMaFlCFiLcCgYEAmAgRsEj4Nh665VPvuZzH\nZIgZMAlwBgHR7/v6l7AbybcVYEXLTNJtrGEEH6/aOL8V9ogwwZuIvb/TEidCkfcf\nzg/pTcGf2My0MiJLk47xO6EgzNdso9mMG5ZYPraBBsuo7NupvWxCp7NyCiOJDqGH\nK5NmhjInjzsjTghIQRq5+qcCgYEAxnm/NjjvslL8F69p/I3cDJ2/RpaG0sMXvbrO\nVWaMryQyWGz9OfNgGIbeMu2Jj90dar6ChcfUmb8lGOi2AZl/VGmc/jqaMKFnElHl\nJ5JyMFicUzPMiG8DBH+gB71W4Iy+BBKwugHBQP2hkytewQ++PtKuP+RjADEz6vCN\n0mv0WS8CgYBnbMRP8wIOLJPRMw/iL9BdMf606X4xbmNn9HWVp2mH9D3D51kDFvls\n7y2vEaYkFv3XoYgVN9ZHDUbM/YTUozKjcAcvz0syLQb8wRwKeo+XSmo09+360r18\nzRugoE7bPl39WdGWaW3td0qf1r9z3sE2iWUTJPRQ3DYpsLOYIgyKmw==\n-----END RSA PRIVATE KEY-----\n"
      nodes:
        "127.0.0.1:50053": 1
      type: roundrobin
#END
--- exec
grpcurl -import-path ./t/grpc_server_example/proto -proto helloworld.proto -plaintext -d '{"name":"apisix"}' 127.0.0.1:1984 helloworld.Greeter.SayHelloBidirectionalStream
--- response_body
{
  "message": "Hello apisix"
}
{
  "message": "stream ended"
}
