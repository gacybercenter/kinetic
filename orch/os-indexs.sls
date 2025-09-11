# Orchestration script to check and create an OpenSearch index for KVM logs if it doesn't exist

# Check if OpenSearch cluster is reachable
check_opensearch_availability:
  http.query:
    - name: https://api.logger.services.gacyberrange.org:443/_cluster/health
    - method: GET
    - username: fluentbit
    - password: {{ pillar['fluentd_password'] }}
    - verify_ssl: True
    - status: 200
    - text: True

# Check if the index exists
check_index_existence:
  http.query:
    - name: https://api.logger.services.gacyberrange.org:443/kvm-logs
    - method: HEAD
    - username: fluentbit
    - password: {{ pillar['fluentd_password'] }}
    - verify_ssl: True
    - status: [200, 404]
    - text: False
    - require:
      - http: check_opensearch_availability
  module.run:
    - name: set_fact
    - facts:
        index_exists: {{ 'True' if grains['http_status'] == 200 else 'False' }}
    - require:
      - http: check_index_existence

# Create the index if it doesn't exist
create_opensearch_index:
  http.query:
    - name: https://api.logger.services.gacyberrange.org:443/kvm-logs
    - method: PUT
    - username: fluentbit
    - password: {{ pillar['fluentd_password'] }}
    - verify_ssl: True
    - data: |
        {
          "settings": {
            "index": {
              "number_of_shards": 1,
              "number_of_replicas": 1
            }
          },
          "mappings": {
            "dynamic": "true",
            "_source": {
              "enabled": true
            },
            "properties": {
              "time": {
                "type": "date",
                "format": "yyyy-MM-dd'T'HH:mm:ss.SSSZ||epoch_millis"
              },
              "log": {
                "type": "text"
              },
              "tag": {
                "type": "keyword"
              }
            }
          }
        }
    - status: 200
    - text: True
    - onlyif:
      - fun: grains.get
        key: index_exists
        value: False
    - require:
      - http: check_opensearch_availability
      - module: check_index_existencew