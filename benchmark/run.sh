#! /bin/bash -x

if [ -n "$1" ]; then
    worker_cnt=$1
else
    worker_cnt=1
fi

mkdir -p benchmark/server/logs

sudo openresty -p $PWD/benchmark/server || exit 1

trap 'onCtrlC' INT
function onCtrlC () {
    sudo openresty -p $PWD/benchmark/server -s stop
}

# 1 worker
sed  -i "s/worker_processes [0-9]*/worker_processes $worker_cnt/g" conf/nginx.conf
make reload

sleep 3

echo -e "\n\n$worker_cnt worker + 1 upstream + no plugin"

curl http://127.0.0.1:9080/apisix/admin/routes/1 -X PUT -d '
{
    "uri": "/hello",
    "plugins": {
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:80": 1
        }
    }
}'

sleep 1

wrk -d 5 -c 16 http://127.0.0.1:9080/hello

sleep 1

wrk -d 5 -c 16 http://127.0.0.1:9080/hello

sleep 1

echo -e "\n\n$worker_cnt worker + 1 upstream + 2 plugins (limit-count + prometheus)"

curl http://127.0.0.1:9080/apisix/admin/routes/1 -X PUT -d '
{
    "uri": "/hello",
    "plugins": {
        "limit-count": {
            "count": 2000000000000,
            "time_window": 60,
            "rejected_code": 503,
            "key": "remote_addr"
        },
        "prometheus": {}
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:80": 1
        }
    }
}'

sleep 1

wrk -d 5 -c 16 http://127.0.0.1:9080/hello

sleep 1

wrk -d 5 -c 16 http://127.0.0.1:9080/hello

sleep 1

# exit

sudo openresty -p $PWD/benchmark/server -s stop || exit 1
