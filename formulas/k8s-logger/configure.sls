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
create_{{ host }}_syslog_conf:
  file.managed:
    - name: /etc/fluent-bit/{{ host }}-syslog-INPUT.conf
    - contents: |
        [INPUT]
            Name                syslog
            Path                /tmp/in_syslog
            Buffer_Chunk_Size   32000
            Buffer_Max_Size     64000
            Receive_Buffer_Size 512000

create_{{ host }}_filesystem_conf:
  file.managed:
    - name: /etc/fluent-bit/{{ host }}-filesys-INPUT.conf
    - contents: |
        [INPUT]
            Name node_exporter_metrics
            metrics filesystem

create_{{ host }}_ssh_service_conf:
  file.managed:
    - name: /etc/fluent-bit/{{ host }}-ssh-service-INPUT.conf
    - contents:  |
        [INPUT]
            Name systemd
            tag  master.ssh
            Path /var/log/journal
            Systemd_Filter  _SYSTEMD_UNIT=ssh.service

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
            Multiline         On
            Multiline_Flush   1s
            Parser            audit_multiline

create_{{ host }}_auth_conf:
  file.managed:
    - name: /etc/fluent-bit/{{ host }}-auth-INPUT.conf
    - contents: |
        [INPUT]
            Name              tail
            Tag               auth.*
            Path              /var/log/auth.log
            DB                /var/log/flb_auth.db
            Parser            syslog
            Refresh_Interval  5

create_{{ host }}_parsers_conf:
  file.managed:
    - name: /etc/fluent-bit/parsers.conf
    - contents: |
        [MULTILINE_PARSER]
            Name              audit_multiline
            Type              regex
            Flush_Timeout     1000
            Rule              "start_state"  "/^type=/"  "cont"

        [PARSER]
            Name        audit
            Format      regex
            Regex       ^type=(?<type>[^ ]+) (?<msg>audit\([^)]+\)): (?<avc>.*) (?<exe>.*) (?<key>.*) (?<auid>[^ ]+) (?<uid>[^ ]+) (?<gid>[^ ]+) (?<euid>[^ ]+) (?<suid>[^ ]+) (?<fsuid>[^ ]+) (?<egid>[^ ]+) (?<sgid>[^ ]+) (?<fsgid>[^ ]+) (?<tty>[^ ]+) (?<ses>[^ ]+) (?<comm>.*) (?<exe_path>.*) (?<pid>[^ ]+) (?<ppid>[^ ]+) (?<uid>[^ ]+) (?<gid>[^ ]+) (?<euid>[^ ]+) (?<suid>[^ ]+) (?<fsuid>[^ ]+) (?<egid>[^ ]+) (?<sgid>[^ ]+) (?<fsgid>[^ ]+) (?<tty>[^ ]+) (?<ses>[^ ]+) (?<arch>[^ ]+) (?<syscall>[^ ]+) (?<success>[^ ]+) (?<exit>[^ ]+) (?<a0>.*) (?<a1>.*) (?<a2>.*) (?<item>[^ ]+) (?<ppid>[^ ]+) (?<pid>[^ ]+) (?<auid>[^ ]+) (?<uid>[^ ]+) (?<gid>[^ ]+) (?<euid>[^ ]+) (?<suid>[^ ]+) (?<fsuid>[^ ]+) (?<egid>[^ ]+) (?<sgid>[^ ]+) (?<fsgid>[^ ]+) (?<tty>[^ ]+) (?<ses>[^ ]+) (?<comm>.*) (?<exe>.*) (?<key>.*)$
            Time_Key   time
            Time_Format %h %d %H:%M:%S

        [PARSER]
            Name        syslog
            Format      regex
            Regex       ^(?<host>[^ ]*) (?<ident>[^ ]*) (?<pid>[^ ]*) (?<msgid>[^ ]*) (?<severity>[^:]*): (?<message>.*)$
            Time_Key    time
            Time_Format %b %d %H:%M:%S

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

create_{{ host }}_opensearch_ssh_output:
  file.managed:
    - name: /etc/fluent-bit/{{ host }}-ssh-OUTPUT.conf
    - contents:  |
        [OUTPUT]
            Name              opensearch
            Match             *ssh*
            Host              api.logger.services.gacyberrange.org
            Port              443
            Index             ssh.service
            Type              _doc
            HTTP_User         fluentbit
            HTTP_Passwd       {{ pillar['fluentd_password'] }}
            TLS               On
            TLS.verify        Off
            Suppress_Type_Name On

create_{{ host }}_opensearch_general_output:
  file.managed:
    - name: /etc/fluent-bit/{{ host }}-general-OUTPUT.conf
    - contents:  |
        [OUTPUT]
            Name              opensearch
            Match             *
            Host              api.logger.services.gacyberrange.org
            Port              443
            Index             {{ grains['host'] }}
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
{% endif %}

fluent-bit-service.dead:
  service.running:
    - name: fluent-bit
    - watch:
      - file: /etc/fluent-bit/*