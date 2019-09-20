[English](stand-alone.md)

## Stand-alone mode

开启 Stand-alone 模式的 APISIX 节点，将不再使用默认的 etcd 作为配置中心。

这种方式比较适合两类用户：
1. kubernetes(k8s)：声明式 API 场景，通过全量 yaml 配置来动态更新修改路由规则。
2. 不同配置中心：配置中心的实现有很多，比如 Consule 等，使用全量 yaml 做中间转换桥梁。

APISIX 节点服务启动后会立刻加载 `conf/config.yaml` 文件中的路由规则到内存，并且每间隔一定时间
（默认 1 秒钟），都会尝试检测文件内容是否有更新，如果有更新则重新加载规则。*注意*：重新加载、更新路由规则时，
均是内存热更新，不会有工作进程的替换。

通过设置 `conf/config.yaml` 中的 `apisix.config_center` 选项为 `yaml` 表示启
用 Stand-alone 模式。

参考下面示例：

```yaml
apisix:
  # ...
  config_center: yaml             # etcd: use etcd to store the config value
                                  # yaml: fetch the config value from local yaml file `/your_path/conf/apisix.yaml`
# ...
```

此外由于目前 Admin API 都是基于 etcd 配置中心解决方案，当开启 Stand-alone 模式后，
Admin API 实际将不起作用。
