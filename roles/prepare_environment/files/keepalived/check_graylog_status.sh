#!/bin/bash

# Check web Graylog status (200 or NOT)
graylog_is_available() {
    status=$(curl --write-out "%{http_code}\n" --silent --insecure --output /dev/null "https://127.0.0.1/")
    if [[ ${status} -eq 200 ]]; then
        return 0
    else
        return 1
    fi
}

# Check the Docker container is up and running
container_is_available() {
    enabled_state=$(docker inspect -f '{{.State.Running}}' "$1")
    disabled_state=$(docker inspect -f '{{and .State.Paused .State.Restarting .State.OOMKilled .State.Dead}}' "$1")
    if [[ ${enabled_state} == "true" ]] && [[ ${disabled_state} == "false" ]]; then
        return 0
    else
        return 1
    fi
}

# Check that the ElasticSearch index is not blocked
index_is_available() {
    get_index_blocks_command="curl -X GET -H \"Content-Type: application/json\" localhost:9200/_all/_settings/index.blocks.read_only_allow_delete"
    index_blocks=$(docker exec -it graylog_elasticsearch_1 bash -c "${get_index_blocks_command}")
    result=$(echo "${index_blocks}" | python -c "import sys, json\

for key, value in json.load(sys.stdin).iteritems():\

    if not (value['settings']['index']['blocks']['read_only_allow_delete']):\
        print key, 'index is blocked;'")
    if [[ -n ${result} ]]; then
        echo "${result}"
        return 1
    else
        return 0
    fi
}

if ! container_is_available "graylog_mongo_1"; then
    echo "Container graylog_mongo_1 not available"
    exit 1
elif ! container_is_available "graylog_web_1"; then
    echo "Container graylog_web_1 not available"
    exit 1
elif ! container_is_available "graylog_elasticsearch_1"; then
    echo "Container graylog_elasticsearch_1 not available"
    exit 1
elif ! container_is_available "graylog_graylog_1"; then
    echo "Container graylog_graylog_1 not available"
    exit 1
elif ! graylog_is_available; then
    echo "Graylog Web not available"
    exit 1
elif ! index_is_available; then
    exit 1
else
    exit 0
fi
