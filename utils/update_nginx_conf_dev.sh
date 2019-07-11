#!/bin/sh

lua_version=`lua -e "print(_VERSION)" 2>/dev/null | grep -o -E "(5.[0-9])"`

if [ -z "$lua_version" ]; then
    echo "Lua 5.x environment (luarocks included) should be installed in advance."
    exit 1
elif [ $lua_version = "5.1" ];then
    echo "Current Lua version is 5.1, skip to update conf/nginx.conf."
    exit
fi

sed s"?lua/5.1?lua/$lua_version?" conf/nginx.conf > conf/nginx.conf.tmp
mv conf/nginx.conf.tmp conf/nginx.conf
echo "updated nginx.conf"
