include:
  - /formulas/{{ grains['role'] }}/install

{% if grains['spawning'] == 0 %}

  {% from 'formulas/common/macros/spawn.sls' import spawnzero_complete with context %}
    {{ spawnzero_complete() }}

{% else %}

check_spawnzero_status:
  module.run:
    - name: spawnzero.check
    - type: {{ grains['type'] }}
    - retry:
        attempts: 10
        interval: 30
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

{% endif %}

etcd_conf:
  file.managed:
{% if grains['os_family'] == 'Debian' %}
    - name: /etc/default/etcd
{% elif grains['os_family'] == 'RedHat' %}
    - name: /etc/etcd/etcd.conf
{% endif %}
    - source: salt://formulas/etcd/files/etcd
    - template: jinja
    - defaults:
        etcd_hosts: |
          "
          {%- for host, addresses in salt['mine.get']('role:etcd', 'network.ip_addrs', tgt_type='grain') | dictsort() -%}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
                {{ host }}=http://{{ address }}:2380
              {%- endif -%}
            {%- endfor -%}
            {% if loop.index < loop.length %},{% endif %}
          {%- endfor %}"
        etcd_name: {{ grains['id'] }}
        etcd_listen: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
        cluster_token: {{ pillar['etcd']['etcd_cluster_token'] }}

etcd_unit_file_update:
  file.line:
    - name: /usr/lib/systemd/system/etcd.service
    - content: After=network-online.target
    - match: After=network.target
    - mode: replace

systemctl daemon-reload:
  cmd.run:
    - onchanges:
      - file: etcd_unit_file_update

etcd_service:
  service.running:
    - name: etcd
    - enable: True
    - watch:
      - file: etcd_conf
