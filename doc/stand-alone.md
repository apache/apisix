[中文](stand-alone-cn.md)

## Stand-alone mode

Turning on the APISIX node in Stand-alone mode will no longer use the default etcd as the configuration center.

This method is more suitable for two types of users:
1. kubernetes(k8s)：Declarative API that dynamically updates the routing rules with a full yaml configuration.
2. Different configuration centers: There are many implementations of the configuration center, such as Consule, etc., using the full yaml file for intermediate conversion.

The routing rules in the `conf/config.yaml` file are loaded into memory immediately after the APISIX node service starts. And every time interval (default 1 second), will try to detect whether the file content is updated, if there is an update, reload the rule.

*Note*: When reloading and updating routing rules, they are all hot memory updates, and there will be no replacement of working processes.

To enable Stand-alone model, we can set `apisix.config_center` to `yaml` in file `conf/config.yaml`.

Refer to the example below:

```yaml
apisix:
  # ...
  config_center: yaml             # etcd: use etcd to store the config value
                                  # yaml: fetch the config value from local yaml file `/your_path/conf/apisix.yaml`
# ...
```

In addition, since the current Admin API is based on the etcd configuration center solution, the Admin API will not actually work when the Stand-alone mode is enabled.
