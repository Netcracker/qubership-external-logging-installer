#!/bin/sh
# keepalived health check for the Graylog stack. The node keeps the virtual IP only while Graylog answers through
# nginx and reports that it takes traffic. The load balancer status covers Graylog, MongoDB, and OpenSearch, because
# Graylog reports DEAD when it cannot process messages.
status="$(curl --silent --insecure --max-time 5 https://127.0.0.1/api/system/lbstatus)" || exit 1
[ "${status}" = "ALIVE" ]
