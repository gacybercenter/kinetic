include:
  - /formulas/{{ grains['role'] }}/install

{% if grains['spawning'] == 0 %}

  {% from 'formulas/common/macros/spawn.sls' import spawnzero_complete with context %}
    {{ spawnzero_complete() }}

{% else %}

  {% from 'formulas/common/macros/spawn.sls' import check_spawnzero_status with context %}
    {{ check_spawnzero_status(grains['type']) }}

{% endif %}

{% if grains['os_family'] == 'Debian' %}

bind_apparmor_modification:
  file.managed:
    - name: /etc/apparmor.d/local/usr.sbin.named
    - source: salt://formulas/bind/files/usr.sbin.named

apparmor_service:
  service.running:
    - name: apparmor
    - watch:
      - file: bind_apparmor_modification

{% endif %}

bind_conf:
  file.managed:
{% if grains['os_family'] == 'Debian' %}
    - name: /etc/bind/named.conf.options
{% elif grains['os_family'] == 'RedHat' %}
    - name: /etc/named.conf
{% endif %}
    - source: salt://formulas/bind/files/named.conf.options
    - template: jinja
    - defaults:
        public_dns: {{ pillar['networking']['addresses']['float_dns'] }}
          {% if salt['mine.get']('role:designate', 'network.ip_addrs', tgt_type='grain')|length %}
        designate_hosts: |-
          {{ ""|indent(10) }}
          {%- for host, addresses in salt['mine.get']('role:designate', 'network.ip_addrs', tgt_type='grain') | dictsort() -%}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
          {{ address }};
              {%- endif -%}
            {%- endfor -%}
          {%- endfor %}
          {% else %}
        designate_hosts: 127.0.0.1;
          {% endif %}
{% if grains['os_family'] == 'Debian' %}
        directory: /var/cache/bind
{% elif grains['os_family'] == 'RedHat' %}
        directory: /var/named
{% endif %}

/etc/designate/rndc.key:
  file.managed:
    - makedirs: True
    - contents_pillar: designate:designate_rndc_key
    - mode: 640
    - user: root
{% if grains['os_family'] == 'Debian' %}
    - group: bind
{% elif grains['os_family'] == 'RedHat' %}
    - group: named
{% endif %}

designate_bind9_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: bind9
{% elif grains['os_family'] == 'RedHat' %}
    - name: named
{% endif %}
    - enable: true
    - watch:
      - file: /etc/designate/rndc.key
      - file: bind_conf
