#  开发者手册

## 在开发环境搭建 APISIX

如果你是开发人员，可以通过下面的命令快速搭建本地开发环境。

```shell
git clone git@github.com:iresty/apisix.git
cd apisix
make dev
```

如果一切顺利，你会在最后看到这样的信息：

> Stopping after installing dependencies for apisix

下面是预期的开发环境目录结构：

```shell
$ tree -L 2 -d apisix
apisix
├── bin
├── conf
├── deps                # 依赖的 Lua 和动态库，放在了这里
│   ├── lib64
│   └── share
├── doc
│   └── images
├── lua
│   └── apisix
├── t
│   ├── admin
│   ├── core
│   ├── lib
│   ├── node
│   └── plugin
└── utils
```

`make` 可以辅助我们完成更多其他功能, 比如:

```shell
$ make help
Makefile rules:

    help:         Show Makefile rules.
    dev:          Create a development ENV
    check:        Check Lua srouce code
    init:         Initialize the runtime environment
    run:          Start the apisix server
    stop:         Stop the apisix server
    clean:        Remove generated files
    reload:       Reload the apisix server
    install:      Install the apisix
```


## 运行测试案例

在你本地运行测试案例：

```shell
make test
```

下面是运行测试的依赖项：

* Nginx: version >= 1.4.2

* Perl modules:
    `Test::Nginx` https://github.com/openresty/test-nginx

更多细节，可以参考 [travis.yml](.travis.yml).
