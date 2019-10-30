# dev-manual

## Install APISIX in development environment

For different operating systems have different dependencies, see detail: [Install Dependencies](install-dependencies.md).

If you are a developer, we can set up a local development environment with the following commands after we installed dependencies.

```shell
git clone git@github.com:iresty/apisix.git
cd apisix

# init submodule
git submodule update --init --recursive

# install dependency
make dev
```

If all goes well, you will see this message at the end:

> Stopping after installing dependencies for apisix

The following is the expected development environment directory structure:

```shell
$ tree -L 2 -d apisix
apisix
├── benchmark
│   ├── fake-apisix
│   └── server
├── bin
├── conf
│   └── cert
├── dashboard
│   ├── css
│   ├── fonts
│   ├── img
│   ├── js
│   └── tinymce
├── deps                    # dependent Lua and dynamic libraries
│   ├── lib64
│   └── share
├── doc
│   ├── images
│   └── plugins
├── logs
├── lua
│   └── apisix
├── rockspec
├── t
│   ├── admin
│   ├── config-center-yaml
│   ├── core
│   ├── lib
│   ├── node
│   ├── plugin
│   ├── router
│   └── servroot
└── utils
```

## Manage (start/stop) APISIX Server

We can start the APISIX server by command `make run` in apisix home folder,
or we can stop APISIX server by command `make stop`.

```shell
# init nginx config file and etcd
$ make init
./bin/apisix init
./bin/apisix init_etcd

# start APISIX server
$ make run

# stop APISIX server
$ make stop

# more actions find by `help`
$ make help
Makefile rules:

    help:         Show Makefile rules.
    dev:          Create a development ENV
    check:        Check Lua source code
    init:         Initialize the runtime environment
    run:          Start the apisix server
    stop:         Stop the apisix server
    restart:      restart the apisix server
    clean:        Remove generated files
    reload:       Reload the apisix server
    install:      Install the apisix
    test:         Run the test case
```

## Test

1. Install perl's package manager `cpanminus` first
2. Then install `test-gninx` via `cpanm`:：`sudo cpanm --notest Test::Nginx IPC::Run > build.log 2>&1 || (cat build.log && exit 1)`
3. Clone source code：`git clone https://github.com/openresty/test-nginx.git`;
4. Load the `test-nginx` library with perl's `prove` command and run the test cases in the `/t` directory:
    * Run the test cases: `prove -Itest-nginx/lib -r t`
    * To set the path of nginx to run the test cases: `TEST_NGINX_BINARY=/usr/local/bin/openresty prove -Itest-nginx/lib -r t`
