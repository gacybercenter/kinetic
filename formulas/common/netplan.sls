/etc/netplan/01-netcfg.yaml:
  file.managed:
    - contents: |
        network:
          version: 2
          renderer: networkd
          ethernets:
{%- for network in pillar['hosts'][grains.item[type]]['networks'] %}
            {{ pillar['hosts']['controller']['networks'][network] }}:
              dhcp4: no
{%- endfor %}
          bridges: 
{%- for network in pillar['hosts']['controller']['networks'] %}
{%- if network == 'management' %}
{%- set useDhcp = 'yes' %}
{%- else %}
{%- set useDhcp = 'no' %}
{%- endif %}
            {{ network }}:
              dhcp4: {{ useDhcp }}
              interfaces:
                - {{ pillar['hosts']['controller']['networks'][network] }}
{%- endfor %}
