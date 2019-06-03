#!/bin/sh

target_file=$1

# 这里的-f参数判断$target_file是否存在
if [ ! -f "$target_file" ]; then
    cp  ./conf/config.yaml  $target_file
fi
