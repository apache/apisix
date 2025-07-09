#!/bin/bash

# Set terminal size to avoid "screen size is bogus" errors
export COLUMNS=80
export LINES=24

# APISIX Route Operations Script
# Features: 1. Create 10k routes 2. Test routes 3. Clean routes

# Configuration
ADMIN_API="http://127.0.0.1:9180"
ADMIN_KEY="RpbzxdBxTEjYagDGDOBXiUCeXiVFxsPd"
APISIX_API="http://127.0.0.1:9080"
ROUTE_COUNT=10
NGINX_CONTAINER="test-nginx"
NGINX_PORT="1980"
UPSTREAM_NODE="127.0.0.1:${NGINX_PORT}"
ETCD_CONTAINER="test-etcd"
ETCD_PORT="2379"

# Baseline load configuration
BASELINE_RATE="8000"

# Create routes
create_routes() {
    echo "Starting to create ${ROUTE_COUNT} routes, upstream node: ${UPSTREAM_NODE}"
    
    for i in $(seq 1 $ROUTE_COUNT); do
        response=$(curl -s -X PUT "${ADMIN_API}/apisix/admin/routes/${i}" \
            -H "X-API-KEY: ${ADMIN_KEY}" \
            -H "Content-Type: application/json" \
            -d "{
                \"uri\": \"/test/${i}\",
                \"methods\": [\"GET\"],
                \"upstream\": {
                    \"type\": \"roundrobin\",
                    \"nodes\": {
                        \"${UPSTREAM_NODE}\": 1
                    }
                }
            }")
        
        # Check if route creation was successful
        if echo "$response" | grep -q '"create_time"' || echo "$response" | grep -q '"update_time"'; then
            # Success - continue
            :
        else
            echo "Error: Failed to create route ${i}"
            echo "Response: $response"
            echo "Route creation aborted at route ${i}"
            exit 1
        fi
        
        if [ $((i % 1000)) -eq 0 ]; then
            echo "Created ${i} routes"
        fi
    done
    
    echo "Route creation completed!"
}

# Test routes
test_routes() {
    echo "Starting to test ${ROUTE_COUNT} routes"
    
    success_count=0
    fail_count=0
    
    for i in $(seq 1 $ROUTE_COUNT); do
        response=$(curl -s -o /dev/null -w "%{http_code}" "${APISIX_API}/test/${i}")
        
        if [ "$response" = "200" ] || [ "$response" = "404" ]; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi
        
        if [ $((i % 1000)) -eq 0 ]; then
            echo "Tested ${i} routes (Success: ${success_count}, Failed: ${fail_count})"
        fi
    done
    
    echo "Route testing completed! Success: ${success_count}, Failed: ${fail_count}"
}

# Clean routes
clean_routes() {
    echo "Starting to clean all routes"
    
    # Get all route IDs
    routes=$(curl -s "${ADMIN_API}/apisix/admin/routes" -H "X-API-KEY: ${ADMIN_KEY}" | \
             grep -o '"key":"[^"]*"' | \
             grep -o '/apisix/routes/[0-9]*' | \
             grep -o '[0-9]*$')
    
    if [ -z "$routes" ]; then
        echo "No routes found"
        return
    fi
    
    count=0
    for route_id in $routes; do
        curl -s -X DELETE "${ADMIN_API}/apisix/admin/routes/${route_id}" \
            -H "X-API-KEY: ${ADMIN_KEY}" > /dev/null
        count=$((count + 1))
        
        if [ $((count % 1000)) -eq 0 ]; then
            echo "Cleaned ${count} routes"
        fi
    done
    
    echo "Route cleanup completed! Total cleaned: ${count} routes"
}

# Enable prometheus plugin
enable_prometheus() {
    echo "Enabling prometheus plugin via global rules"
    
    response=$(curl -s -X PUT "${ADMIN_API}/apisix/admin/global_rules/1" \
        -H "X-API-KEY: ${ADMIN_KEY}" \
        -H "Content-Type: application/json" \
        -d '{
            "plugins": {
                "prometheus": {
                    "prefer_name": true
                }
            }
        }')

    echo "$response"
    
    if echo "$response" | grep -q '"create_time"'; then
        echo "Prometheus plugin enabled successfully"
        echo "Metrics URL: http://127.0.0.1:9091/apisix/prometheus/metrics"
    else
        echo "Failed to enable prometheus plugin"
        echo "Response: $response"
    fi
}

# Start nginx service
start_nginx() {
    echo "Starting test nginx service"
    
    # Check if container already exists
    if docker ps -a --format '{{.Names}}' | grep -q "^${NGINX_CONTAINER}$"; then
        echo "Stopping and removing existing container: ${NGINX_CONTAINER}"
        docker stop "${NGINX_CONTAINER}" > /dev/null 2>&1
        docker rm "${NGINX_CONTAINER}" > /dev/null 2>&1
    fi
    
    # Create temporary nginx config file
    TEMP_NGINX_CONF="/tmp/nginx_${NGINX_CONTAINER}.conf"
    cat > "${TEMP_NGINX_CONF}" << 'EOF'
master_process on;

worker_processes 1;

events {
    worker_connections 4096;
}

http {
    resolver ipv6=off 8.8.8.8;

    access_log off;
    server_tokens off;
    keepalive_requests 10000000;

    server {
        listen 1980;
        server_name _;

        location / {
            return 200 "hello\n";
        }
    }
}
EOF
    
    # Start new container
    docker run -d \
        --name "${NGINX_CONTAINER}" \
        -p "${NGINX_PORT}:${NGINX_PORT}" \
        -v "${TEMP_NGINX_CONF}:/etc/nginx/nginx.conf:ro" \
        nginx:alpine > /dev/null
    
    if [ $? -eq 0 ]; then
        echo "Nginx service started"
        echo "Container name: ${NGINX_CONTAINER}"
        echo "Access URL: http://127.0.0.1:${NGINX_PORT}"
        echo "Test command: curl http://127.0.0.1:${NGINX_PORT}"
    else
        echo "Failed to start nginx service"
        # Clean up temporary config file
        rm -f "${TEMP_NGINX_CONF}"
        exit 1
    fi
}

# Stop nginx service
stop_nginx() {
    echo "Stopping test nginx service"
    
    if docker ps --format '{{.Names}}' | grep -q "^${NGINX_CONTAINER}$"; then
        docker stop "${NGINX_CONTAINER}" > /dev/null
        docker rm "${NGINX_CONTAINER}" > /dev/null
        echo "Nginx service stopped and container removed: ${NGINX_CONTAINER}"
    else
        echo "Nginx container not running or doesn't exist"
    fi
    
    # Clean up temporary config file
    TEMP_NGINX_CONF="/tmp/nginx_${NGINX_CONTAINER}.conf"
    if [ -f "${TEMP_NGINX_CONF}" ]; then
        rm -f "${TEMP_NGINX_CONF}"
        echo "Temporary config file cleaned"
    fi
}

# Initialize etcd service
init_etcd() {
    echo "Initializing etcd service"
    
    # Check if container already exists
    if docker ps -a --format '{{.Names}}' | grep -q "^${ETCD_CONTAINER}$"; then
        echo "Stopping and removing existing container: ${ETCD_CONTAINER}"
        docker stop "${ETCD_CONTAINER}" > /dev/null 2>&1
        docker rm "${ETCD_CONTAINER}" > /dev/null 2>&1
    fi
    
    # Start etcd container (reference APISIX official config)
    docker run -d \
        --name "${ETCD_CONTAINER}" \
        -p "${ETCD_PORT}:2379" \
        -e ETCD_DATA_DIR=/etcd_data \
        -e ETCD_ENABLE_V2=true \
        -e ALLOW_NONE_AUTHENTICATION=yes \
        -e ETCD_ADVERTISE_CLIENT_URLS=http://127.0.0.1:2379 \
        -e ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379 \
        bitnami/etcd:3.6 > /dev/null
    
    if [ $? -eq 0 ]; then
        echo "Etcd service started"
        echo "Client URL: http://127.0.0.1:${ETCD_PORT}"
        
        # Wait for etcd to start
        echo "Waiting for etcd service to start..."
        sleep 3
        
        # Verify etcd is running properly
        if curl -s "http://127.0.0.1:${ETCD_PORT}/version" > /dev/null; then
            echo "Etcd service is running normally"
        else
            echo "Warning: etcd service may not be fully started, please wait a moment"
        fi
    else
        echo "Failed to start etcd service"
        exit 1
    fi
}

# Test single route
test_route() {
    route_id="$1"
    if [ -z "$route_id" ]; then
        echo "Please provide route ID"
        echo "Usage: $0 test-route <route_id>"
        echo "Example: $0 test-route 1"
        exit 1
    fi
    
    echo "Testing route /test/${route_id}"
    response=$(curl -s -w "\nHTTP_CODE:%{http_code}\nTIME:%{time_total}s" "${APISIX_API}/test/${route_id}")
    echo "$response"
}

# Get route configuration
get_route() {
    route_id="$1"
    if [ -z "$route_id" ]; then
        echo "Please provide route ID"
        echo "Usage: $0 get-route <route_id>"
        echo "Example: $0 get-route 1"
        exit 1
    fi
    
    echo "Getting configuration for route ${route_id}"
    response=$(curl -s "${ADMIN_API}/apisix/admin/routes/${route_id}" -H "X-API-KEY: ${ADMIN_KEY}")
    
    if echo "$response" | grep -q '"key"'; then
        echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
    else
        echo "Route doesn't exist or failed to get"
        echo "$response"
    fi
}

# Monitor APISIX processes (privileged agent and workers)
monitor_apisix() {
    local monitor_file="$1"
    
    echo "timestamp,process_type,pid,cpu_percent,memory_percent" > "$monitor_file"
    
    while true; do
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        
        # Find APISIX privileged agent process
        privileged_pid=$(ps aux | grep -v grep | grep "privileged agent" | awk '{print $2}' | head -1)
        if [ -n "$privileged_pid" ]; then
            # Use ps to get CPU and memory for privileged agent
            ps_output=$(ps -p "$privileged_pid" -o %cpu,%mem --no-headers 2>/dev/null)
            if [ -n "$ps_output" ]; then
                cpu=$(echo "$ps_output" | awk '{print $1}')
                mem=$(echo "$ps_output" | awk '{print $2}')
                echo "$timestamp,privileged_agent,$privileged_pid,$cpu,$mem" >> "$monitor_file"
            fi
        fi
        
        # Find APISIX master process PID first
        master_pid=$(ps aux | grep -v grep | grep "nginx: master process" | grep "apisix" | awk '{print $2}' | head -1)
        if [ -n "$master_pid" ]; then
            # Find worker processes that are children of APISIX master
            worker_pids=$(ps --ppid "$master_pid" -o pid --no-headers | grep -E "^[[:space:]]*[0-9]+$" | tr -d ' ')
            for worker_pid in $worker_pids; do
                # Verify it's actually a worker process
                if ps -p "$worker_pid" -o cmd --no-headers | grep -q "worker process"; then
                    # Use ps to get CPU and memory for each worker
                    ps_output=$(ps -p "$worker_pid" -o %cpu,%mem --no-headers 2>/dev/null)
                    if [ -n "$ps_output" ]; then
                        cpu=$(echo "$ps_output" | awk '{print $1}')
                        mem=$(echo "$ps_output" | awk '{print $2}')
                        echo "$timestamp,worker,$worker_pid,$cpu,$mem" >> "$monitor_file"
                    fi
                fi
            done
        fi
        
        sleep 1
    done
}

# Generate monitoring summary with averages
generate_monitoring_summary() {
    local monitor_file="$1"
    local summary_file="$2"
    
    if [ ! -f "$monitor_file" ] || [ ! -s "$monitor_file" ]; then
        echo "No monitoring data available"
        return
    fi
    
    # Calculate averages for privileged agent
    privileged_stats=$(grep "privileged_agent" "$monitor_file" | tail -n +1)
    if [ -n "$privileged_stats" ]; then
        avg_cpu=$(echo "$privileged_stats" | awk -F',' '{sum+=$4; count++} END {if(count>0) printf "%.1f", sum/count; else print "0"}')
        avg_mem=$(echo "$privileged_stats" | awk -F',' '{sum+=$5; count++} END {if(count>0) printf "%.1f", sum/count; else print "0"}')
        privileged_pid=$(echo "$privileged_stats" | head -1 | awk -F',' '{print $3}')
        
        echo "Privileged Agent (PID: $privileged_pid): CPU ${avg_cpu}%, Memory ${avg_mem}%" >> "$summary_file"
    fi
    
    # Get individual worker PIDs and calculate averages for each
    worker_pids=$(grep "worker" "$monitor_file" | awk -F',' '{print $3}' | sort -u)
    worker_count=$(echo "$worker_pids" | wc -w)
    
    if [ -n "$worker_pids" ] && [ "$worker_count" -gt 0 ]; then
        # Overall worker statistics
        all_worker_stats=$(grep "worker" "$monitor_file")
        if [ -n "$all_worker_stats" ]; then
            overall_avg_cpu=$(echo "$all_worker_stats" | awk -F',' '{sum+=$4; count++} END {if(count>0) printf "%.1f", sum/count; else print 0"}')
            overall_avg_mem=$(echo "$all_worker_stats" | awk -F',' '{sum+=$5; count++} END {if(count>0) printf "%.1f", sum/count; else print 0"}')
            
            echo "Workers ($worker_count processes): CPU ${overall_avg_cpu}%, Memory ${overall_avg_mem}%" >> "$summary_file"
        fi
    fi
    
    echo "Files: $monitor_file | $(basename "$summary_file")" >> "$summary_file"
}

# wrk benchmark prometheus metrics
benchmark_metrics() {
    local metrics_url="http://127.0.0.1:9091/apisix/prometheus/metrics"
    local file_prefix="${1:-default}"
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local monitor_file="/tmp/apisix_monitor_${file_prefix}_${timestamp}.log"
    local summary_file="/tmp/apisix_summary_${file_prefix}_${timestamp}.log"
    
    # Skip the file_prefix parameter for wrk
    shift
    
    # Check if wrk is installed
    if ! command -v wrk &> /dev/null; then
        echo "Error: wrk not installed"
        exit 1
    fi
    
    # Check if wrk.lua exists
    if [ ! -f "wrk.lua" ]; then
        echo "Error: wrk.lua script not found"
        exit 1
    fi
    
    # Start fresh baseline load for this test
    echo "Starting baseline load (${BASELINE_RATE} req/s) and establishing load for 30s..."
    nohup bash -c "wrk -t 8 -c 1000 -R '${BASELINE_RATE}' -s wrk.lua '${APISIX_API}'" >/dev/null 2>&1 &
    local baseline_pid=$!
    
    sleep 30
    
    # Start monitoring in background
    monitor_apisix "$monitor_file" &
    monitor_pid=$!
    
    # Ensure cleanup of monitoring and baseline load on function exit
    trap "kill $monitor_pid $baseline_pid 2>/dev/null" RETURN
    
    echo "Running metrics benchmark..."
    
    # Run wrk benchmark against metrics endpoint
    wrk "$@" "${metrics_url}"
    
    # Stop monitoring and baseline load
    kill $monitor_pid $baseline_pid 2>/dev/null
    sleep 1
    
    echo ""
    echo "📊 Performance Summary:"
    
    # Generate and display summary
    generate_monitoring_summary "$monitor_file" "$summary_file"
    cat "$summary_file"
    
    # Clean up monitoring trap only
    trap - RETURN
    echo "Monitor file: $monitor_file"
    echo "Summary file: $summary_file"
}

# Main logic
case "$1" in
    "create")
        create_routes
        ;;
    "test")
        test_routes
        ;;
    "clean")
        clean_routes
        ;;
    "prometheus")
        enable_prometheus
        ;;
    "start-nginx")
        start_nginx
        ;;
    "stop-nginx")
        stop_nginx
        ;;
    "init-etcd")
        init_etcd
        ;;
    "test-route")
        test_route "$2"
        ;;
    "get-route")
        get_route "$2"
        ;;
    "benchmark-metrics")
        shift  # Remove first parameter "benchmark-metrics"
        if [ $# -eq 0 ]; then
            # No parameters provided, use defaults
            echo "Using default parameters: -t 2 -c 10 -d 30s -R 50"
            benchmark_metrics "default" -t 2 -c 10 -d "30s" -R "50"
        elif [[ "$1" == -* ]]; then
            # No file prefix provided, use default
            benchmark_metrics "default" "$@"
        else
            # File prefix provided
            benchmark_metrics "$@"
        fi
        ;;
    "benchmark")
        echo "🔧 Test 1: Single Connection"
        benchmark_metrics "single_conn" -t 1 -c 1 -d 30s -R "50"

        echo "🔧 Test 2: Three Connections"
        benchmark_metrics "three_conn" -t 3 -c 3 -d "30s" -R "50"
        ;;
esac
