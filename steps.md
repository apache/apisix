# What to do?

- Write a test that checks the following behaviour: When nodes backed by upstream go from 2 to 1, then on further request fetch_healthchecker is called
and the previous healthchecker is released stopping the errors from healthchecker.

- Create a Kubernetes route with an upstream backed by 2 nodes and an active healthchecker.

- Reduce the returned no of nodes to 1.

-


# How to do?

- active healthchecker with tcp timeout of 20 times with 1 second gap.
- mock create_endpoint_lrucache to first return localhost:8989/8990.
- stop server on 8989
- send request again on apisix GET /t, this should trigger recreation of healthchecker.
- wait 20 seconds.
- There should be no error log unhealthy TCP increment (20/20)


