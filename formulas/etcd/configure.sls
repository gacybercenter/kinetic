include:
  - formulas/etcd/install
  - formulas/common/base
  - formulas/common/networking

{% if grains['spawning'] == 0 %}

spawnzero_complete:
  event.send:
    - name: {{ grains['type'] }}/spawnzero/complete
    - data: "{{ grains['type'] }} spawnzero is complete."

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
          {%- for host, address in salt['mine.get']('role:etcd', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
          ETCD_INITIAL_CLUSTER="{{ host }}=http://{{ address[0] }}:2380"
          {%- endfor %}
        etcd_name: {{ grains['id'] }}
        etcd_listen: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}

etcd_service:
  service.running:
    - name: etcd
    - enable: true
    - watch:
      - file: etcd_conf
