[中文](plugin-develop-cn.md)

# 目录
- [**check dependencies**](#check dependencies)
- [**name and config**](#*name and config)
- [**schema and check**](#schema and check)
- [**choose phase to run**](#choose phase to run)
- [**implement the logic**](#implement the logic)
- [**write test case**](#write test case)


## check dependencies

If you have dependencies on external libraries, check the license first and add the license to the COPYRIGHT file.

## name and config

Determine the name and priority of the plugin, and add to conf/config.yaml;

## schema and check

Write schema descriptions and check functions;

## choose phase to run

Determine which phase to run, generally access or rewrite; 

## implement the logic

Write the logic of the plugin in the corresponding phase;

## write test case

For functions, write and improve the test cases of various dimensions, do a comprehensive test for your plugin!
