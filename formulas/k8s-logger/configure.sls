{% set role = grains.get('type') %}
{% set host = grains.get('host') %}
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
            Record          host ${HOSTNAME}
        [FILTER]
            Name            lua
            Match           audit.*
            Script          /etc/fluent-bit/audit_parser.lua
            Call            cb_filter

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
