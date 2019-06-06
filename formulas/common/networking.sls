{% if grains['virtual'] == 'physical' %}
  {% set srv = 'hosts' %}
{% else %}
  {% set srv = 'virtual' %}
/etc/netplan/50-cloud-init.yaml:
  file.absent
{% endif %}

{% set management_address_octets = grains['ipv4'][0].split('.') %}

{% if grains['osfinger'] == 'Ubuntu-18.04' %}
/etc/netplan/01-netcfg.yaml:
  file.managed:
    - contents: |
        network:
          version: 2
          renderer: networkd
          ethernets:
  {%- if pillar[srv][grains['type']]['networks']['bridge'] == false %}
    {%- for binding in pillar[srv][grains['type']]['networks']['bindings'] %}
      {%- for network in binding %}
        {%- if network == 'management' %}
            {{ binding[network] }}:
              dhcp4: yes
        {%- elif grains['type'] == 'cache' and network == 'public' %}
            {{ binding[network] }}:
              addresses: [{{ pillar['subnets']['cache_public_ip'] }}]
              dhcp4: no
        {%- else %}
          {%- set target_subnet = pillar['subnets'][network] %}
          {%- set target_subnet_netmask = target_subnet.split('/') %}
          {%- set target_subnet_octets = target_subnet_netmask[0].split('.') %}
            {{ binding[network] }}:
              addresses: [{{ target_subnet_octets[0]}}.{{ target_subnet_octets[1]}}.{{ management_address_octets[2]}}.{{ management_address_octets[3]}}/{{ target_subnet_netmask[1]}}]
              dhcp4: no
        {%- endif %}
      {%- endfor %}
    {%- endfor %}
  {%- else %}
    {%- for binding in pillar[srv][grains['type']]['networks']['bindings'] %}
      {%- for network in binding %}
            {{ binding[network] }}:
              dhcp4: no
      {%- endfor %}
    {%- endfor %}
          bridges: 
    {%- for binding in pillar[srv][grains['type']]['networks']['bindings'] %}
      {%- for network in binding %}
            {{ network }}:
        {%- if network == 'management' %}
              dhcp4: yes
        {%- elif network == 'public' %}
              dhcp4: no
        {%- else %}
          {%- set target_subnet = pillar['subnets'][network] %}
          {%- set target_subnet_netmask = target_subnet.split('/') %}
          {%- set target_subnet_octets = target_subnet_netmask[0].split('.') %}
              dhcp4: no
              addresses: [{{ target_subnet_octets[0]}}.{{ target_subnet_octets[1]}}.{{ management_address_octets[2]}}.{{ management_address_octets[3]}}/{{ target_subnet_netmask[1]}}]
        {%- endif %}
              interfaces:
                - {{ binding[network] }}
      {%- endfor %}
    {%- endfor %}
  {%- endif %}
{% else %}
placeholder for ifupdown:
  test.nop
{% endif %}

networking_mine_update:
  module.run:
    - name: mine.update
  event.send:
    - name: {{ grains['type'] }}/mine/address/update
    - data: "{{ grains['type'] }} mine has been updated."

