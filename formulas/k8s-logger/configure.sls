# State formula to configure OpenSearch for logging with Fluent Bit
# Ensures cluster health, creates an index for KVM logs, sets up a role with permissions,
# and maps the Fluent Bit user to the role.
{% set role = grains.get('type') %}
# Check OpenSearch cluster health before proceeding
check_opensearch_health:
  opensearch.cluster_health:
    - name: check_opensearch_health
    - admin_user: {{ pillar.get('opensearch_admin_user', 'admin') }}
    - admin_password: {{ pillar.get('fluentd_password') }}
    - host: {{ pillar.get('opensearch_host', 'https://api.logger.services.gacyberrange.org:443') }}

# Create or ensure the index for KVM logs exists
# Use hostname from grains if opensearch_index_name is empty
{% set index_name = pillar.get('opensearch_index_name', grains.get('host')) %}
create_kvm_logs_index:
  opensearch.index_present:
    - name: create_{{ index_name }}_index
    - index_name: {{ index_name }}
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
    - name: create_fluentbit_{{ index_name }}_role
    - role_name: {{ pillar.get('opensearch_role_name', 'fluentbit_role') }}
    - index_name: {{ index_name }}
    - admin_user: {{ pillar.get('opensearch_admin_user', 'admin') }}
    - admin_password: {{ pillar.get('fluentd_password') }}
    - host: {{ pillar.get('opensearch_host', 'https://api.logger.services.gacyberrange.org:443') }}
    - require:
      - opensearch: create_{{ index_name }}_index

# Map the Fluent Bit user to the role for access to the index
map_fluentbit_user_to_role:
  opensearch.user_role_mapping_present:
    - name: map_fluentbit_user_to_{{ index_name }}_role
    - role_name: {{ pillar.get('opensearch_role_name', 'fluentbit_role') }}
    - user_name: {{ pillar.get('opensearch_user_name', 'fluentbit') }}
    - admin_user: {{ pillar.get('opensearch_admin_user', 'admin') }}
    - admin_password: {{ pillar.get('fluentd_password', '') }}
    - host: {{ pillar.get('opensearch_host', 'https://api.logger.services.gacyberrange.org:443') }}
    - require:
      - opensearch: create_fluentbit_{{ index_name }}_role

{% if role == 'controller' %}
{% set vm_result = salt['kinetic-libvirt.list_vms'](connection_uri=pillar.get('libvirt_connection_uri', 'qemu:///system')) %}
{% set vms = vm_result.get('vms') %}
{% for vm in vms %}
{% set bmh_data = pillar.get('bmh', {}).get(vm, {}) %}
{% set ip = bmh_data.get('network', {}).get('management_ip', '') if bmh_data else '' %}
create_health_{{ vm }}_conf:
  file.managed:
    - name: /etc/fluent-bit/{{ vm }}-vm-health.conf
    - content: |
        [INPUT]
          Name health
          Host {{ ip }}
          Tag {{ vm }}.health
          Port 22
          Interval_Sec  10
          Interval_NSec 0
          Add_Host true
{% endfor %}
{% endif %}
create_syslog_forward:
  file.managed:
    - name: /etc/fluent-bit/fluent-bit.conf
    - template: jinja
    - source: salt://formulas/k8s-logger/files/fluent-bit.j2

fluent-bit-service.dead:
  service.running:
    - name: fluent-bit
    - watch:
      - file: /etc/fluent-bit/*