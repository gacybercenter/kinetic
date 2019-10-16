#!/bin/bash

echo "Waiting for graylog to listen on tcp 9000.."
counter=0
while ! nc -z {{ http_bind_address }} 9000; do
    ((counter++))
    if [ $counter -gt 30 ]
    then
        exit 255
    else
    sleep 10
    fi
done

### This script will configure the graylog2 cluster as outlined below

### Obtain session token using admin user/password stored in pillar.  Place in
### session_token variable

session_token=$(curl -s                                           \
-H 'X-Requested-By: graylog'                                      \
-H 'Content-Type: application/json'                               \
-H 'Accept: application/json'                                     \
-X POST 'http://{{ http_bind_address }}:9000/api/system/sessions' \
-d                                                                \
'{
  "username":"admin",
  "password":"{{ password_secret }}",
  "host":""
}'                                                                \
 | jq -r '.session_id')

### Configure Inputs
### Check for existing input
curl -u $session_token:session                                    \
-H 'X-Requested-By: graylog'                                      \
-H 'Content-Type: application/json'                               \
-X GET http://{{ http_bind_address }}:9000/api/system/inputs      \
| jq '.inputs | .[].title'                                        \
| grep -q "Kinetic UDP Input"

## If no current input, create it
## else, exit
if [ $? -eq 1 ]
then
  echo -n "Created input: "
  curl -u $session_token:session                                  \
  -H 'X-Requested-By: graylog'                                    \
  -H 'Content-Type: application/json'                             \
  -X POST http://{{ http_bind_address }}:9000/api/system/inputs   \
  -d                                                              \
  '{
    "title": "Kinetic UDP Input",
    "global": true,
    "type": "org.graylog2.inputs.syslog.udp.SyslogUDPInput",
    "configuration": {
      "expand_structured_data" : false,
      "recv_buffer_size" : 262144,
      "port" : 5514,
      "override_source" : null,
      "force_rdns" : false,
      "allow_override_date" : true,
      "bind_address" : "{{ http_bind_address }}",
      "store_full_message" : true
    },
    "node": "null"
  }'
else
  echo "Input already exists...exiting"
  exit 0
fi
