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
use t::APISIX 'no_plan';

repeat_each(1);
log_level('debug');
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    my $yaml_config = $block->yaml_config // <<_EOC_;
apisix:
    node_listen: 1984
    config_center: yaml
    enable_admin: false
_EOC_

    $block->set_value("yaml_config", $yaml_config);

    my $routes = <<_EOC_;
routes:
  -
    uri: /hello
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
_EOC_

    $block->set_value("apisix_yaml", $block->apisix_yaml . $routes);

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests();

__DATA__

=== TEST 1: sanity
--- apisix_yaml
ssl:
    -
        cert: |
            -----BEGIN CERTIFICATE-----
            MIIDrzCCApegAwIBAgIJAI3Meu/gJVTLMA0GCSqGSIb3DQEBCwUAMG4xCzAJBgNV
            BAYTAkNOMREwDwYDVQQIDAhaaGVqaWFuZzERMA8GA1UEBwwISGFuZ3pob3UxDTAL
            BgNVBAoMBHRlc3QxDTALBgNVBAsMBHRlc3QxGzAZBgNVBAMMEmV0Y2QuY2x1c3Rl
            ci5sb2NhbDAeFw0yMDEwMjgwMzMzMDJaFw0yMTEwMjgwMzMzMDJaMG4xCzAJBgNV
            BAYTAkNOMREwDwYDVQQIDAhaaGVqaWFuZzERMA8GA1UEBwwISGFuZ3pob3UxDTAL
            BgNVBAoMBHRlc3QxDTALBgNVBAsMBHRlc3QxGzAZBgNVBAMMEmV0Y2QuY2x1c3Rl
            ci5sb2NhbDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAJ/qwxCR7g5S
            s9+VleopkLi5pAszEkHYOBpwF/hDeRdxU0I0e1zZTdTlwwPy2vf8m3kwoq6fmNCt
            tdUUXh5Wvgi/2OA8HBBzaQFQL1Av9qWwyES5cx6p0ZBwIrcXQIsl1XfNSUpQNTSS
            D44TGduXUIdeshukPvMvLWLezynf2/WlgVh/haWtDG99r/Gj3uBdjl0m/xGvKvIv
            NFy6EdgG9fkwcIalutjrUnGl9moGjwKYu4eXW2Zt5el0d1AHXUsqK4voe0p+U2Nz
            quDmvxteXWdlsz8o5kQT6a4DUtWhpPIfNj9oZfPRs3LhBFQ74N70kVxMOCdec1lU
            bnFzLIMGlz0CAwEAAaNQME4wHQYDVR0OBBYEFFHeljijrr+SPxlH5fjHRPcC7bv2
            MB8GA1UdIwQYMBaAFFHeljijrr+SPxlH5fjHRPcC7bv2MAwGA1UdEwQFMAMBAf8w
            DQYJKoZIhvcNAQELBQADggEBAG6NNTK7sl9nJxeewVuogCdMtkcdnx9onGtCOeiQ
            qvh5Xwn9akZtoLMVEdceU0ihO4wILlcom3OqHs9WOd6VbgW5a19Thh2toxKidHz5
            rAaBMyZsQbFb6+vFshZwoCtOLZI/eIZfUUMFqMXlEPrKru1nSddNdai2+zi5rEnM
            HCot43+3XYuqkvWlOjoi9cP+C4epFYrxpykVbcrtbd7TK+wZNiK3xtDPnVzjdNWL
            geAEl9xrrk0ss4nO/EreTQgS46gVU+tLC+b23m2dU7dcKZ7RDoiA9bdVc4a2IsaS
            2MvLL4NZ2nUh8hAEHiLtGMAV3C6xNbEyM07hEpDW6vk6tqk=
            -----END CERTIFICATE-----
        key: |
            -----BEGIN PRIVATE KEY-----
            MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQCf6sMQke4OUrPf
            lZXqKZC4uaQLMxJB2DgacBf4Q3kXcVNCNHtc2U3U5cMD8tr3/Jt5MKKun5jQrbXV
            FF4eVr4Iv9jgPBwQc2kBUC9QL/alsMhEuXMeqdGQcCK3F0CLJdV3zUlKUDU0kg+O
            Exnbl1CHXrIbpD7zLy1i3s8p39v1pYFYf4WlrQxvfa/xo97gXY5dJv8RryryLzRc
            uhHYBvX5MHCGpbrY61JxpfZqBo8CmLuHl1tmbeXpdHdQB11LKiuL6HtKflNjc6rg
            5r8bXl1nZbM/KOZEE+muA1LVoaTyHzY/aGXz0bNy4QRUO+De9JFcTDgnXnNZVG5x
            cyyDBpc9AgMBAAECggEAatcEtehZPJaCeClPPF/Cwbe9YoIfe4BCk186lHI3z7K1
            5nB7zt+bwVY0AUpagv3wvXoB5lrYVOsJpa9y5iAb3GqYMc/XDCKfD/KLea5hwfcn
            BctEn0LjsPVKLDrLs2t2gBDWG2EU+udunwQh7XTdp2Nb6V3FdOGbGAg2LgrSwP1g
            0r4z14F70oWGYyTQ5N8UGuyryVrzQH525OYl38Yt7R6zJ/44FVi/2TvdfHM5ss39
            SXWi00Q30fzaBEf4AdHVwVCRKctwSbrIOyM53kiScFDmBGRblCWOxXbiFV+d3bjX
            gf2zxs7QYZrFOzOO7kLtHGua4itEB02497v+1oKDwQKBgQDOBvCVGRe2WpItOLnj
            SF8iz7Sm+jJGQz0D9FhWyGPvrN7IXGrsXavA1kKRz22dsU8xdKk0yciOB13Wb5y6
            yLsr/fPBjAhPb4h543VHFjpAQcxpsH51DE0b2oYOWMmz+rXGB5Jy8EkP7Q4njIsc
            2wLod1dps8OT8zFx1jX3Us6iUQKBgQDGtKkfsvWi3HkwjFTR+/Y0oMz7bSruE5Z8
            g0VOHPkSr4XiYgLpQxjbNjq8fwsa/jTt1B57+By4xLpZYD0BTFuf5po+igSZhH8s
            QS5XnUnbM7d6Xr/da7ZkhSmUbEaMeHONSIVpYNgtRo4bB9Mh0l1HWdoevw/w5Ryt
            L/OQiPhfLQKBgQCh1iG1fPh7bbnVe/HI71iL58xoPbCwMLEFIjMiOFcINirqCG6V
            LR91Ytj34JCihl1G4/TmWnsH1hGIGDRtJLCiZeHL70u32kzCMkI1jOhFAWqoutMa
            7obDkmwraONIVW/kFp6bWtSJhhTQTD4adI9cPCKWDXdcCHSWj0Xk+U8HgQKBgBng
            t1HYhaLzIZlP/U/nh3XtJyTrX7bnuCZ5FhKJNWrYjxAfgY+NXHRYCKg5x2F5j70V
            be7pLhxmCnrPTMKZhik56AaTBOxVVBaYWoewhUjV4GRAaK5Wc8d9jB+3RizPFwVk
            V3OU2DJ1SNZ+W2HBOsKrEfwFF/dgby6i2w6MuAP1AoGBAIxvxUygeT/6P0fHN22P
            zAHFI4v2925wYdb7H//D8DIADyBwv18N6YH8uH7L+USZN7e4p2k8MGGyvTXeC6aX
            IeVtU6fH57Ddn59VPbF20m8RCSkmBvSdcbyBmqlZSBE+fKwCliKl6u/GH0BNAWKz
            r8yiEiskqRmy7P7MY9hDmEbG
            -----END PRIVATE KEY-----
        sni: "test.com"
--- config
listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;

location /t {
    content_by_lua_block {
        -- sync
        ngx.sleep(0.2)

        do
            local sock = ngx.socket.tcp()

            sock:settimeout(2000)

            local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local sess, err = sock:sslhandshake(nil, "test.com", false)
            if not sess then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end

            local req = "GET /hello HTTP/1.0\r\nHost: test.com\r\nConnection: close\r\n\r\n"
            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send http request: ", err)
                return
            end

            local line, err = sock:receive()
            if not line then
                ngx.say("failed to receive: ", err)
                return
            end

            ngx.say("received: ", line)

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        end  -- do
        -- collectgarbage()
    }
}
--- response_body
received: HTTP/1.1 200 OK
close: 1 nil
--- error_log
lua ssl server name: "test.com"
