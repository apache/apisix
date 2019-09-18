# dev-manual

## Install APISIX in development environment

For different operating systems have different dependencies, see detail: [Install Dependencies](doc/install-dependencies.md).

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
    dev_r3:       Create a development ENV for r3
    check:        Check Lua source code
    init:         Initialize the runtime environment
    run:          Start the apisix server
    stop:         Stop the apisix server
    clean:        Remove generated files
    reload:       Reload the apisix server
    install:      Install the apisix
    test:         Run the test case
```


## Test

Running the test cases at local machine:

```shell
make test
```

The following dependencies are required to run the test suite:

* Nginx: version >= 1.4.2

* Perl modules:
    `Test::Nginx` https://github.com/openresty/test-nginx

For the detail on how to install dependencies, please take a look at [travis.yml](.travis.yml).
