# State formula to configure OpenSearch for logging with Fluent Bit
# Ensures cluster health, creates an index for KVM logs, sets up a role with permissions,
# and maps the Fluent Bit user to the role.

# Check OpenSearch cluster health before proceeding
check_opensearch_health:
  opensearch.cluster_health:
    - name: check_opensearch_health
    - admin_user: {{ pillar.get('opensearch_admin_user', 'admin') }}
    - admin_password: {{ pillar.get('fluentd_password', '') }}
    - host: {{ pillar.get('opensearch_host', 'https://api.logger.services.gacyberrange.org:443') }}

# Create or ensure the index for KVM logs exists
create_kvm_logs_index:
  opensearch.index_present:
    - name: create_kvm_logs_index
    - index_name: {{ pillar.get('opensearch_index_name') }}
    - admin_user: {{ pillar.get('opensearch_admin_user', 'admin') }}
    - admin_password: {{ pillar.get('fluentd_password') }}
    - host: {{ pillar.get('opensearch_host', 'https://api.logger.services.gacyberrange.org:443') }}
    - shards: {{ pillar.get('opensearch_shards', 1) }}
    - replicas: {{ pillar.get('opensearch_replicas', 1) }}
    - require:
      - opensearch: check_opensearch_health

# Create or ensure a role with permissions for the KVM logs index
create_fluentbit_role:
  opensearch.role_present:
    - name: create_fluentbit_role
    - role_name: {{ pillar.get('opensearch_role_name', 'fluentbit_role') }}
    - index_name: {{ pillar.get('opensearch_index_name', 'kvm-logs') }}
    - admin_user: {{ pillar.get('opensearch_admin_user', 'admin') }}
    - admin_password: {{ pillar.get('fluentd_password', '') }}
    - host: {{ pillar.get('opensearch_host', 'https://api.logger.services.gacyberrange.org:443') }}
    - require:
      - opensearch: create_kvm_logs_index

# Map the Fluent Bit user to the role for access to the index
map_fluentbit_user_to_role:
  opensearch.user_role_mapping_present:
    - name: map_fluentbit_user_to_role
    - role_name: {{ pillar.get('opensearch_role_name', 'fluentbit_role') }}
    - user_name: {{ pillar.get('opensearch_user_name', 'fluentbit') }}
    - admin_user: {{ pillar.get('opensearch_admin_user', 'admin') }}
    - admin_password: {{ pillar.get('fluentd_password', '') }}
    - host: {{ pillar.get('opensearch_host', 'https://api.logger.services.gacyberrange.org:443') }}
    - require:
      - opensearch: create_fluentbit_role