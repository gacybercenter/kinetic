{% if grains['osfinger'] == 'Ubuntu-18.04' %}
/etc/netplan/01-netcfg.yaml:
  file.managed:
    - contents: |
        network:
          version: 2
          renderer: networkd
          ethernets:
{% if pillar['hosts'][grains['type']]['networks']['bridge'] == false %}
{%- for network, interface in pillar['hosts'][grains['type']]['networks']['bindings'].items() %}
{%- if network == 'management' %}
{%- set useDhcp = 'yes' %}
{%- else %}
{%- set useDhcp = 'no' %}
{%- endif %}
            {{ network }}{{ interface }}:
              dhcp4: {{ useDhcp }}
{%- endfor %}
{%- else %}
    {%- for network in pillar['hosts'][grains['type']]['networks'] %}
            {{ pillar['hosts'][grains['type']]['networks'][network] }}:
              dhcp4: no
{%- endfor %}
          bridges: 
{%- for network in pillar['hosts'][grains['type']]['networks'] %}
{%- if network == 'management' %}
{%- set useDhcp = 'yes' %}
{%- else %}
{%- set useDhcp = 'no' %}
{%- endif %}
            {{ network }}:
              dhcp4: {{ useDhcp }}
              interfaces:
                - {{ pillar['hosts'][grains['type']]['networks'][network] }}
{%- endfor %}
{%- endif %}

netplan apply:
  cmd.run:
    - onchanges:
      - /etc/netplan/01-netcfg.yaml

restart_minion:
  service.running:
    - name: salt-minion
    - watch:
      - cmd: netplan apply

{% else %}
placeholder for ifupdown:
  test.nop
{% endif %}
