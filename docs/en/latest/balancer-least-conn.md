---
title: Least Connection Load Balancer
keywords:
  - APISIX
  - API Gateway
  - Routing
  - Least Connection
  - Upstream
description: This document introduces the Least Connection Load Balancer (`least_conn`) in Apache APISIX, including its working principle, configuration methods, and use cases.
---

<!--
#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
-->

## Overview

The `least_conn` load balancer in Apache APISIX provides two modes of operation:

1. **Traditional Mode** (default): A weighted round-robin algorithm optimized for performance
2. **Persistent Connection Counting Mode**: True least-connection algorithm that maintains accurate connection counts across balancer recreations

This algorithm is particularly effective for scenarios where request processing times vary significantly or when dealing with long-lived connections such as WebSocket connections, where the second mode provides significant benefits for load distribution after upstream scaling.

## Algorithm Details

### Core Principle

#### Traditional Mode (Default)

In traditional mode, the algorithm uses a weighted round-robin approach with dynamic scoring:

- Initialize each server with score = `1 / weight`
- On connection: increment score by `1 / weight`
- On completion: decrement score by `1 / weight`

This provides good performance for most use cases while maintaining backward compatibility.

#### Persistent Connection Counting Mode

When enabled, the algorithm maintains accurate connection counts for each upstream server in shared memory:

- Tracks real connection counts across configuration reloads
- Survives upstream node scaling operations
- Provides true least-connection behavior for long-lived connections

The algorithm uses a binary min-heap data structure to efficiently track and select servers with the lowest scores.

### Score Calculation

#### Traditional Mode

```lua
-- Initialization
score = 1 / weight

-- On connection
score = score + (1 / weight)

-- On completion
score = score - (1 / weight)
```

#### Persistent Connection Counting Mode

```lua
-- Initialization and updates
score = (connection_count + 1) / weight
```

Where:

- `connection_count` - Current number of active connections to the server (persisted)
- `weight` - Server weight configuration value

Servers with lower scores are preferred for new connections. In persistent mode, the `+1` represents the potential new connection being considered.

### Connection State Management

#### Traditional Mode

- **Connection Start**: Score updated to `score + (1 / weight)`
- **Connection End**: Score updated to `score - (1 / weight)`
- **State**: Maintained only within current balancer instance
- **Heap Maintenance**: Binary heap automatically reorders servers by score

#### Persistent Connection Counting Mode

- **Connection Start**: Connection count incremented, score updated to `(new_count + 1) / weight`
- **Connection End**: Connection count decremented, score updated to `(new_count - 1) / weight`
- **Score Protection**: Prevents negative scores by setting minimum score to 0
- **Heap Maintenance**: Binary heap automatically reorders servers by score

##### Persistence Strategy

Connection counts are stored in nginx shared dictionary with structured keys:

```
conn_count:{upstream_id}:{server_address}
```

This ensures connection state survives:

- Upstream configuration changes
- Balancer instance recreation
- Worker process restarts
- Upstream node scaling operations
- Node additions/removals

### Connection Tracking

#### Persistent State Management

The balancer uses nginx shared dictionary (`balancer-least-conn`) to maintain connection counts across:

- Balancer instance recreations
- Upstream configuration changes
- Worker process restarts
- Node additions/removals

#### Connection Count Keys

Connection counts are stored using structured keys:

```
conn_count:{upstream_id}:{server_address}
```

Where:

- `upstream_id` - Unique identifier for the upstream configuration
- `server_address` - Server address (e.g., "127.0.0.1:8080")

#### Upstream ID Generation

1. **Primary**: Uses `upstream.id` if available
2. **Fallback**: Generates CRC32 hash of stable JSON encoding of upstream configuration

```lua
local upstream_id = upstream.id
if not upstream_id then
    upstream_id = ngx.crc32_short(dkjson.encode(upstream))
end
```

The implementation uses `dkjson.encode` instead of `core.json.encode` to ensure deterministic JSON serialization, which is crucial for generating consistent upstream IDs across different worker processes and configuration reloads.

### Connection Lifecycle

#### 1. Connection Establishment

When a new request is routed:

1. Select server with lowest score from the heap
2. Update server score to `(current_count + 1) / weight`
3. Increment connection count in shared dictionary
4. Update server position in the heap

#### 2. Connection Completion

When a request completes:

1. Calculate new score as `(current_count - 1) / weight`
2. Ensure score is not negative (minimum 0)
3. Decrement connection count in shared dictionary
4. Update server position in the heap

#### 3. Cleanup Process

During balancer recreation:

1. Identify current active servers
2. Remove connection counts for servers no longer in upstream
3. Preserve counts for existing servers

### Data Structures

#### Binary Heap

- **Type**: Min-heap based on server scores
- **Purpose**: Efficient selection of server with lowest score
- **Operations**: O(log n) insertion, deletion, and updates

#### Shared Dictionary

- **Name**: `balancer-least-conn`
- **Size**: 10MB (configurable)
- **Scope**: Shared across all worker processes
- **Persistence**: Survives configuration reloads

## Configuration

### Automatic Setup

The `balancer-least-conn` shared dictionary is automatically configured by APISIX with a default size of 10MB. No manual configuration is required.

### Custom Configuration

To customize the shared dictionary size, modify the `nginx_config.http.lua_shared_dict` section in your `conf/config.yaml`:

```yaml
nginx_config:
  http:
    lua_shared_dict:
      balancer-least-conn: 20m  # Custom size (default: 10m)
```

### Upstream Configuration

#### Traditional Mode (Default)

```yaml
upstreams:
  - id: 1
    type: least_conn
    nodes:
      "127.0.0.1:8080": 1
      "127.0.0.1:8081": 2
      "127.0.0.1:8082": 1
```

#### Persistent Connection Counting Mode

##### WebSocket Load Balancing

For WebSocket and other long-lived connection scenarios, it's recommended to enable persistent connection counting for better load distribution:

```yaml
upstreams:
  - id: websocket_upstream
    type: least_conn
    scheme: websocket
    persistent_conn_counting: true  # Explicitly enable persistent counting
    nodes:
      "127.0.0.1:8080": 1
      "127.0.0.1:8081": 1
      "127.0.0.1:8082": 1
```

##### Manual Activation

```yaml
upstreams:
  - id: custom_upstream
    type: least_conn
    persistent_conn_counting: true  # Explicitly enable persistent counting
    nodes:
      "127.0.0.1:8080": 1
      "127.0.0.1:8081": 1
      "127.0.0.1:8082": 1
```

## Performance Characteristics

### Time Complexity

- **Server Selection**: O(1) - heap peek operation
- **Connection Update**: O(log n) - heap update operation
- **Cleanup**: O(k) where k is the number of stored keys

### Memory Usage

- **Per Server**: ~100 bytes (key + value + overhead)
- **Total**: Scales linearly with number of servers across all upstreams

### Scalability

- **Servers**: Efficiently handles hundreds of servers per upstream
- **Upstreams**: Supports multiple upstreams with isolated connection tracking
- **Requests**: Minimal per-request overhead

## Use Cases

### Traditional Mode

#### Optimal Scenarios

1. **High-throughput HTTP APIs**: Fast, short-lived connections
2. **Microservices**: Request/response patterns
3. **Standard web applications**: Regular HTTP traffic

#### Advantages

- Lower memory usage
- Better performance for short connections
- Simple configuration

### Persistent Connection Counting Mode

#### Optimal Scenarios

1. **WebSocket Applications**: Long-lived connections benefit from accurate load distribution across scaling operations
2. **Server-Sent Events (SSE)**: Persistent streaming connections
3. **Long-polling**: Extended HTTP connections
4. **Variable Processing Times**: Requests with unpredictable duration
5. **Database Connection Pools**: Connection-oriented services

#### Use After Node Scaling

Particularly beneficial when:

- Adding new upstream nodes to existing deployments
- Existing long connections remain on original nodes
- Need to balance load across all available nodes

### Considerations

1. **Short-lived Connections**: Traditional mode has lower overhead for very short requests
2. **Memory Usage**: Persistent mode requires shared memory for connection state
3. **Backward Compatibility**: Traditional mode maintains existing behavior

## WebSocket Load Balancing Improvements

### Problem Addressed

Prior to this enhancement, when upstream nodes were scaled out (e.g., from 2 to 3 nodes), WebSocket load balancing experienced imbalanced distribution:

- Existing WebSocket long connections remained on original nodes
- New connections were distributed across all nodes
- Result: Original nodes overloaded, new nodes underutilized

### Solution

The persistent connection counting mode specifically addresses this by:

1. **Tracking Real Connections**: Maintains accurate connection counts in shared memory
2. **Surviving Scaling Events**: Connection counts persist through upstream configuration changes
3. **Balancing New Connections**: New connections automatically route to less loaded nodes
4. **Gradual Rebalancing**: As connections naturally terminate and reconnect, load evens out

### Example Scenario

**Before Enhancement:**

```
Initial: Node1(50 conn), Node2(50 conn)
After scaling to 3 nodes: Node1(50 conn), Node2(50 conn), Node3(0 conn)
New connections distributed: Node1(60 conn), Node2(60 conn), Node3(40 conn)
```

**With Persistent Counting:**

```
Initial: Node1(50 conn), Node2(50 conn)
After scaling to 3 nodes: Node1(50 conn), Node2(50 conn), Node3(0 conn)
New connections route to Node3 until balanced: Node1(50 conn), Node2(50 conn), Node3(50 conn)
```

## Monitoring and Debugging

### Log Messages

#### Debug Logs

Enable debug logging to monitor balancer behavior:

**Balancer Creation**

```
creating new least_conn balancer for upstream: upstream_123
```

**Connection Count Operations**

```
generated connection count key: conn_count:upstream_123:127.0.0.1:8080
retrieved connection count for 127.0.0.1:8080: 5
setting connection count for 127.0.0.1:8080 to 6
incrementing connection count for 127.0.0.1:8080 by 1, new count: 6
```

**Server Selection**

```
selected server: 127.0.0.1:8080 with current score: 1.2
after_balance for server: 127.0.0.1:8080, before_retry: false
```

**Cleanup Operations**

```
cleaning up stale connection counts for upstream: upstream_123
cleaned up stale connection count for server: 127.0.0.1:8082
```

#### Initialization

```
initializing server 127.0.0.1:8080 with weight 1, base_score 1, conn_count 0, final_score 1
```

#### Errors

```
failed to set connection count for 127.0.0.1:8080: no memory
failed to increment connection count for 127.0.0.1:8080: no memory
```

### Shared Dictionary Monitoring

Check shared dictionary usage:

```lua
local dict = ngx.shared["balancer-least-conn"]
local free_space = dict:free_space()
local capacity = dict:capacity()
```

## Error Handling

### Missing Shared Dictionary

If the shared dictionary is not available (which should not happen with default configuration), the balancer will fail to initialize with:

```
shared dict 'balancer-least-conn' not found
```

### Memory Exhaustion

When shared dictionary runs out of memory:

- Connection count updates will fail
- Warning messages will be logged
- Balancer continues to function with potentially stale counts

### Recovery Strategies

1. **Increase Dictionary Size**: Allocate more memory
2. **Cleanup Frequency**: Implement periodic cleanup of stale entries
3. **Monitoring**: Set up alerts for dictionary usage

## Best Practices

### Configuration

1. **Dictionary Size**: Default 10MB is sufficient for most cases (supports ~100k connections)
2. **Server Weights**: Use appropriate weights to reflect server capacity
3. **Health Checks**: Combine with health checks for robust load balancing

### Monitoring

1. **Connection Counts**: Monitor for unexpected accumulation
2. **Memory Usage**: Track shared dictionary utilization
3. **Performance**: Measure request distribution effectiveness

### Troubleshooting

1. **Uneven Distribution**: Check for connection count accumulation
2. **Memory Issues**: Monitor shared dictionary free space
3. **Configuration**: Verify shared dictionary is properly configured

## Migration and Compatibility

### Backward Compatibility

- **Fully Backward Compatible**: Existing configurations maintain original behavior with no changes
- **Explicit Opt-in**: New features are only enabled when `persistent_conn_counting: true` is configured
- **Graceful Degradation**: Automatically falls back to traditional mode when shared dictionary is unavailable
- **No Breaking Changes**: No modifications to existing APIs or configuration formats

### Upgrade Considerations

1. **Configuration**: Shared dictionary is automatically configured
2. **Memory**: Default allocation should be sufficient for most use cases
3. **Testing**: Validate load distribution in staging environment
