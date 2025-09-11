# Orchestration script to check and create an OpenSearch index for KVM logs if it doesn't exist

# Check if OpenSearch cluster is reachable
check_opensearch_availability:
  http.query:
    - name: https://api.logger.services.gacyberrange.org:443/_cluster/health
    - method: GET
    - username: fluentbit
    - password: {{ pillar['fluentd_password'] }}
    - verify_ssl: False
    - status: 200
    - text: True

# Check if the index exists
check_index_existence:
  http.query:
    - name: https://api.logger.services.gacyberrange.org:443/kvm-logs
    - method: HEAD
    - username: fluentbit
    - password: {{ pillar['fluentd_password'] }}
    - verify_ssl: False
    - status: [200]
    - text: False
    - require:
      - http: check_opensearch_availability

# Create the index if it doesn't exist
# create_opensearch_index:
#   http.query:
#     - name: https://api.logger.services.gacyberrange.org:443/kvm-logs
#     - method: PUT
#     - username: fluentbit
#     - password: {{ pillar['fluentd_password'] }}
#     - verify_ssl: False
#     - data: |
#         {
#           "settings": {
#             "index": {
#               "number_of_shards": 1,
#               "number_of_replicas": 1
#             }
#           },
#           "mappings": {
#             "dynamic": "true",
#             "_source": {
#               "enabled": true
#             },
#             "properties": {
#               "time": {
#                 "type": "date",
#                 "format": "yyyy-MM-dd'T'HH:mm:ss.SSSZ||epoch_millis"
#               },
#               "log": {
#                 "type": "text"
#               },
#               "tag": {
#                 "type": "keyword"
#               }
#             }
#           }
#         }
#     - header:
#         Content-Type: application/json
#     - status: 200
#     - text: True
#     - unless: check_index_existence
#     - require:
#       - http: check_opensearch_availability

create_opensearch_index_cmd:
  cmd.run:
    - name: |
        curl -ku fluentbit:{{ pillar['fluentd_password'] }} -X PUT "https://api.logger.services.gacyberrange.org:443/kvm-logs" -H "Content-Type: application/json" -d '{"settings": {"index": {"number_of_shards": 1, "number_of_replicas": 1}}, "mappings": {"dynamic": "true", "_source": {"enabled": true}, "properties": {"time": {"type": "date", "format": "yyyy-MM-dd'\''T'\''HH:mm:ss.SSSZ||epoch_millis"}, "log": {"type": "text"}, "tag": {"type": "keyword"}}}}'
    - require:
      - http: check_opensearch_availability
    - unless: check_index_existence