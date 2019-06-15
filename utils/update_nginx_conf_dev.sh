#!/bin/sh

lua_version=`lua -e "print(_VERSION)" | grep -o -E "(5.[0-9])"`

if [ $lua_version = "5.1" ];then
    echo "current Lua version is 5.1, skip to update conf/nginx.conf"
    exit
fi

sed s"?lua/5.1?lua/$lua_version?" conf/nginx.conf > conf/nginx.conf.tmp
mv conf/nginx.conf.tmp conf/nginx.conf
echo "updated nginx.conf"
