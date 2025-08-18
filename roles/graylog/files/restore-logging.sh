#!/bin/bash
restore_vault=$1
status_file=/srv/docker/graylog/restore.successful
echo 'restore from' $restore_vault
sudo docker stop graylog_web_1 graylog_graylog_1 graylog_elasticsearch_1 graylog_storage_1 graylog_mongo_1
sudo rm -rf /srv/docker/graylog/*
curl -X POST -v -H "Content-Type: application/json" -d '{"vault":"'$restore_vault'", "dbs":["db1"]}' localhost:8080/restore

until [ -f $status_file ]; do
    echo 'wait for restore command ending'
    sleep 10
done
rm -f $status_file
echo 'Data restored successfully. Starting containers'
sudo systemctl restart docker
echo 'Restore finished'
exit
