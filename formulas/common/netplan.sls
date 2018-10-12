/etc/netplan/01-netcfg.yaml:
  file.managed:
    - contents: |
        network:
          version: 2
          renderer: networkd
          ethernets:
{%- for network in pillar['hosts']['controller']['networks'] %}
            {{ pillar['hosts']['controller']['networks'][network] }}:
              dhcp4: no
          bridges:
            {{ network }}:
              dhcp4: yes
                interfaces:
                  - {{ pillar['hosts']['controller']['networks'][network] }}
{%- endfor %}
