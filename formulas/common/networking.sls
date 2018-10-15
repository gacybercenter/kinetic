{% if grains['osfinger'] == 'Ubuntu-18.04' %}
/etc/netplan/01-netcfg.yaml:
  file.managed:
    - contents: |
        network:
          version: 2
          renderer: networkd
          ethernets:
  {%- if pillar['hosts'][grains['type']]['networks']['bridge'] == false %}
    {%- for binding in pillar['hosts'][grains['type']]['networks']['bindings'] %}
      {%- for network in binding %}
        {%- if network == 'management' %}
          {%- set useDhcp = 'yes' %}
        {%- else %}
          {%- set useDhcp = 'no' %}
        {%- endif %}
            {{ binding[network] }}:
              dhcp4: {{ useDhcp }}
      {%- endfor %}
    {%- endfor %}
  {%- else %}
    {%- for binding in pillar['hosts'][grains['type']]['networks']['bindings'] %}
      {%- for network in binding %}
            {{ binding[network] }}:
              dhcp4: no
      {%- endfor %}
    {%- endfor %}
          bridges: 
    {%- for binding in pillar['hosts'][grains['type']]['networks']['bindings'] %}
      {%- for network in binding %}
        {%- if network == 'management' %}
          {%- set useDhcp = 'yes' %}
        {%- else %}
          {%- set useDhcp = 'no' %}
        {%- endif %}
            {{ network }}:
              dhcp4: {{ useDhcp }}
              interfaces:
                - {{ binding[network] }}
      {%- endfor %}
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
