include:
  - /formulas/etcd/install
  - /formulas/common/base
  - /formulas/common/networking

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

### I have no idea why I need to do it this way instead of including
### the enabled: True key in service.running, but the etcd0 spawn0
### refuses to be enabled after the completion of the orch run
### when using an integrated enabled.  I have not encountered this on any
### other service.  It works correctly consistently with this method
etcd_service_enable:
  service.enabled:
    - name: etcd

etcd_service:
  service.running:
    - name: etcd
    - enabled: True
    - watch:
      - file: etcd_conf
