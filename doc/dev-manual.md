# dev-manual

## Install APISIX in development environment

If you are a developer, you can set up a local development environment with the following commands.

```shell
git clone git@github.com:iresty/apisix.git
cd apisix
make dev
```

If all goes well, you will see this message at the end:

> Stopping after installing dependencies for apisix

The following is the expected development environment directory structure:

```shell
$ tree -L 2 -d apisix
apisix
├── bin
├── conf
├── deps                # dependent Lua and dynamic libraries
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

We can use more actions in the `make` command, for example:

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
