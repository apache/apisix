#! /bin/bash -x

if [ -n "$1" ]; then
    worker_cnt=$1
else
    worker_cnt=1
fi

trap 'onCtrlC' INT
function onCtrlC () {
    killall wrk
    killall openresty
    openresty -p $PWD/benchmark/server -s stop
    sudo docker stop envoy
}

function run_wrk() {
    connections=`expr $worker_cnt \* 16`
    wrk -d 5 -t $worker_cnt -c ${connections} http://127.0.0.1:10000/hello
}

openresty -p $PWD/benchmark/server || exit 1

sudo docker run --name=envoy --rm -d \
    --network=host \
    -v $(pwd)/config.yaml:/etc/envoy/envoy.yaml \
    envoyproxy/envoy:v1.14-latest  -c /etc/envoy/envoy.yaml --concurrency ${worker_cnt}

sleep 1

curl http://127.0.0.1:10000/hello

sleep 1

run_wrk

sleep 1

run_wrk

sleep 1

onCtrlC
