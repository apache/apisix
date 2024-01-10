use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_shuffle();
no_root_location();
add_block_preprocessor(sub {
    my ($block) = @_;


    my $yaml_config = $block->yaml_config // <<_EOC_;
apisix:
    node_listen: 1984
    enable_admin: false
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
_EOC_

    $block->set_value("yaml_config", $yaml_config);
});
run_tests;
__DATA__
=== TEST 1:  test_pojo
--- apisix_yaml
upstreams:
    - nodes:
        - host: 127.0.0.1
          port: 30880
          weight: 1
      type: roundrobin
      id: 1
routes:
  -
    uri: /t
    plugins:
        http-dubbo:
            service_name: org.apache.dubbo.backend.DubboSerializationTestService
            params_type_desc: Lorg/apache/dubbo/backend/DubboSerializationTestService$AllDataTypesPOJO;
            serialized: true
            method: testPoJo
    upstream_id: 1
#END

--- request
POST /t
{"aBoolean":true,"aByte":1,"aDouble":1.1,"aFloat":1.2,"aInt":2,"aLong":3,"aShort":4,"aString":"aa","acharacter":"a","poJoMap":{"key":"value"},"strings":["aa","bb"]}
--- response_body
{"aBoolean":true,"aByte":1,"aDouble":1.1,"aFloat":1.2,"aInt":2,"aLong":3,"aShort":4,"aString":"aa","acharacter":"a","poJoMap":{"key":"value"},"strings":["aa","bb"]}

=== TEST 2:  test_pojos
--- apisix_yaml
upstreams:
    - nodes:
        - host: 127.0.0.1
          port: 30880
          weight: 1
      type: roundrobin
      id: 1
routes:
  -
    uri: /t
    plugins:
        http-dubbo:
            service_name: org.apache.dubbo.backend.DubboSerializationTestService
            params_type_desc: [Lorg/apache/dubbo/backend/DubboSerializationTestService$AllDataTypesPOJO;
            serialized: true
            method: testPoJos
    upstream_id: 1
#END
--- request
POST /t
{"aBoolean":true,"aByte":1,"aDouble":1.1,"aFloat":1.2,"aInt":2,"aLong":3,"aShort":4,"aString":"aa","acharacter":"a","poJoMap":{"key":"value"},"strings":["aa","bb"]}
--- response_body
[{"aBoolean":true,"aByte":1,"aDouble":1.1,"aFloat":1.2,"aInt":2,"aLong":3,"aShort":4,"aString":"aa","acharacter":"a","poJoMap":{"key":"value"},"strings":["aa","bb"]}]
