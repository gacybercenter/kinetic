include:
  - formulas/bind/install
  - formulas/common/base
  - formulas/common/networking

{% if grains['spawning'] == 0 %}

spawnzero_complete:
  event.send:
    - name: {{ grains['type'] }}/spawnzero/complete
    - data: "{{ grains['type'] }} spawnzero is complete."

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
        designate_hosts: |-
          {{ ""|indent(10) }}
          {% for host, addresses in salt['mine.get']('role:designate', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
            {%- for address in addresses -%}
              {% if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
          {{ address }};
              {% endif %}
            {% endfor %}
          {% endfor %}
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
