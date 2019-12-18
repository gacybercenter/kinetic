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
    - source: salt://formulas/designate/files/named.conf.options
    - template: jinja
    - defaults:
        public_dns: {{ pillar['networking']['addresses']['float_dns'] }}
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
