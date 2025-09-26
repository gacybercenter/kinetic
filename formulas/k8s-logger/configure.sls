# State formula to configure OpenSearch for logging with Fluent Bit
# Ensures cluster health, creates an index for KVM logs, sets up a role with permissions,
# and maps the Fluent Bit user to the role.
{% set role = grains.get('type') %}
{% set host = grains.get('host') %}
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
    - role_name: {{ index_name }}
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
    - role_name: {{ index_name }}
    - user_name: {{ pillar.get('opensearch_user_name', 'fluentbit') }}
    - admin_user: {{ pillar.get('opensearch_admin_user', 'admin') }}
    - admin_password: {{ pillar.get('fluentd_password', '') }}
    - host: {{ pillar.get('opensearch_host', 'https://api.logger.services.gacyberrange.org:443') }}
    - require:
      - opensearch: create_fluentbit_{{ index_name }}_role

map_fluentbit_user_to_audit_role:
  opensearch.user_role_mapping_present:
    - name: map_fluentbit_user_to_audit_logs_role
    - role_name: audit-logs
    - user_name: {{ pillar.get('opensearch_user_name', 'fluentbit') }}
    - admin_user: {{ pillar.get('opensearch_admin_user', 'admin') }}
    - admin_password: {{ pillar.get('fluentd_password', '') }}
    - host: {{ pillar.get('opensearch_host', 'https://api.logger.services.gacyberrange.org:443') }}
    - require:
      - opensearch: create_fluentbit_audit_role

# Create or ensure a role with permissions for the audit-logs index
create_fluentbit_audit_role:
  opensearch.role_present:
    - name: create_fluentbit_audit_logs_role
    - role_name: audit-logs
    - index_name: audit-logs
    - admin_user: {{ pillar.get('opensearch_admin_user', 'admin') }}
    - admin_password: {{ pillar.get('fluentd_password') }}
    - host: {{ pillar.get('opensearch_host', 'https://api.logger.services.gacyberrange.org:443') }}
    - require:
      - opensearch: create_audit_logs_index

# Create or ensure the index for audit logs exists
create_audit_logs_index:
  opensearch.index_present:
    - name: create_audit_logs_index
    - index_name: audit-logs
    - admin_user: {{ pillar.get('opensearch_admin_user', 'admin') }}
    - admin_password: {{ pillar.get('fluentd_password') }}
    - host: {{ pillar.get('opensearch_host', 'https://api.logger.services.gacyberrange.org:443') }}
    - shards: {{ pillar.get('opensearch_shards', 1) }}
    - replicas: {{ pillar.get('opensearch_replicas', 1) }}
    - require:
      - opensearch: check_opensearch_health

{% if role == 'controller' %}
{% set vm_result = salt['kinetic-libvirt.list_vms'](connection_uri=pillar.get('libvirt_connection_uri', 'qemu:///system')) %}
{% set vms = vm_result.get('vms') %}
{% for vm in vms %}
{% set bmh_data = pillar.get('bmh', {}).get(vm, {}) %}
{% set ip = bmh_data.get('network', {}).get('management_ip', '') if bmh_data else '' %}
{% endfor %}
{% endif %}
{% set Kernel = grains.get('kernel') %}
{% if Kernel == "Linux" %}
# New configurations for audit and auth logs
create_{{ host }}_audit_conf:
  file.managed:
    - name: /etc/fluent-bit/{{ host }}-audit-INPUT.conf
    - contents: |
        [INPUT]
            Name              tail
            Tag               audit.*
            Path              /var/log/audit/audit.log
            DB                /var/log/flb_audit.db
            Mem_Buf_Limit     5MB
            Skip_Long_Lines   On
            Refresh_Interval  10
            Parser            audit

        [FILTER]
            Name            record_modifier
            Match           audit.*
            Record          tag audit
create_{{ host }}_auth_conf:
  file.managed:
    - name: /etc/fluent-bit/{{ host }}-auth-INPUT.conf
    - contents: |
        [INPUT]
            Name              tail
            Tag               auth.*
            Path              /var/log/auth.log
            DB                /var/log/flb_auth.db
            Parser            auth
            Refresh_Interval  5

        [FILTER]
            Name            record_modifier
            Match           auth.*
            Record          tag auth

create_{{ host }}_parsers_conf:
  file.managed:
    - name: /etc/fluent-bit/parsers.conf
    - contents: |
        # Regex Parser for Audit Fields (Extracts AU-3 Essentials: Time, Type, User, Path)
        [PARSER]
            Name        audit
            Format      regex
            Regex       ^type=(?<type>[^\s]+)\s+(?<log>.*)$
            Time_Key    msg
            Time_Format audit\(%F:%T\.%N:%s\):
            Time_Keep   On
        [PARSER]
            Name        auth
            Format      regex
            Regex       (?<time>\S+) (?<hostname>\S+) (?<process>.+?(?=\[)|.+?(?=))[^a-zA-Z0-9](?<pid>\d{1,7}|)[^a-zA-Z0-9]{1,3}(?<info>.*)$
            Time_Key    time
            Time_Format %Y-%m-%dT%H:%M:%S.%L%z
            Time_Keep   On

create_{{ host }}_filters_conf:
  file.managed:
    - name: /etc/fluent-bit/{{ host }}-filters.conf
    - contents: |
        [FILTER]
            Name            record_modifier
            Match           *
            Record          hostname ${HOSTNAME}
            Record          source_host ${HOSTNAME}

        [FILTER]
            Name            grep
            Match           audit.*
            Regex           type USER_AUTH|SYSCALL
            Exclude         type CRED_ACQ

create_{{ host }}_opensearch_audit_output:
  file.managed:
    - name: /etc/fluent-bit/{{ host }}-audit-OUTPUT.conf
    - contents:  |
        [OUTPUT]
            Name              opensearch
            Match             audit.*
            Host              api.logger.services.gacyberrange.org
            Port              443
            Index             audit-logs-%Y.%m.%d
            Type              _doc
            HTTP_User         fluentbit
            HTTP_Passwd       {{ pillar['fluentd_password'] }}
            TLS               On
            TLS.verify        Off
            Suppress_Type_Name On

create_{{ host }}_opensearch_auth_output:
  file.managed:
    - name: /etc/fluent-bit/{{ host }}-auth-OUTPUT.conf
    - contents:  |
        [OUTPUT]
            Name              opensearch
            Match             auth.*
            Host              api.logger.services.gacyberrange.org
            Port              443
            Index             audit-logs-%Y.%m.%d
            Type              _doc
            HTTP_User         fluentbit
            HTTP_Passwd       {{ pillar['fluentd_password'] }}
            TLS               On
            TLS.verify        Off
            Suppress_Type_Name On

create_fluent-bit:
  file.managed:
    - name: /etc/fluent-bit/fluent-bit.conf
    - template: jinja
    - source: salt://formulas/k8s-logger/files/fluent-bit.j2
create_lua_parser_script:
  file.managed:
    - name: /etc/fluent-bit/audit_parser.lua
    - source: salt://formulas/k8s-logger/files/audit_parser.lua
{% endif %}

fluent-bit-service:
  service.running:
    - name: fluent-bit
    - watch:
      - file: /etc/fluent-bit/*