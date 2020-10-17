include:
  - /formulas/{{ grains['role'] }}/install

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}
{% import 'formulas/common/macros/constructor.sls' as constructor with context %}

{% if grains['spawning'] == 0 %}

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

### Gateway configuration
{% if salt['pillar.get']('danos:enabled', False) == True %}
set haproxy group:
  danos.set_resourcegroup:
    - name: haproxy-group
    - type: address-group
    - description: list of current haproxy servers
    - values:
      - {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
    - username: {{ pillar['danos']['username'] }}
    - password: {{ pillar['danos_password'] }}
  {% if salt['pillar.get']('danos:endpoint', "gateway") == "gateway" %}
    - host: {{ grains['ip4_gw'] }}
  {% else %}
    - host: {{ pillar['danos']['endpoint'] }}
  {% endif %}

  {% if salt['mine.get']('G@role:share and G@build_phase:configure', 'network.ip_addrs', tgt_type='compound')|length != 0 %}
set nfs group:
  danos.set_resourcegroup:
    - name: manila-share-servers
    - type: address-group
    - description: list of current nfs-ganesha servers
    - values:
    {% for host, addresses in salt['mine.get']('G@role:share and G@build_phase:configure', 'network.ip_addrs', tgt_type='compound') | dictsort() %}
      {%- for address in addresses if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
      - {{ address }}
      {%- endfor -%}
    {% endfor %}
    - username: {{ pillar['danos']['username'] }}
    - password: {{ pillar['danos_password'] }}
    {% if salt['pillar.get']('danos:endpoint', "gateway") == "gateway" %}
    - host: {{ grains['ip4_gw'] }}
    {% else %}
    - host: {{ pillar['danos']['endpoint'] }}
    {% endif %}
  {% endif %}

set haproxy static-mapping:
  danos.set_statichostmapping:
    - name: {{ pillar['haproxy']['dashboard_domain'] }}
    - address: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
    - aliases:
      - {{ pillar['haproxy']['console_domain'] }}
      - {{ pillar['haproxy']['docs_domain'] }}
    - username: {{ pillar['danos']['username'] }}
    - password: {{ pillar['danos_password'] }}
  {% if salt['pillar.get']('danos:endpoint', "gateway") == "gateway" %}
    - host: {{ grains['ip4_gw'] }}
  {% else %}
    - host: {{ pillar['danos']['endpoint'] }}
  {% endif %}
{% endif %}

{% if (salt['grains.get']('selinux:enabled', False) == True) and (salt['grains.get']('selinux:enforced', 'Permissive') == 'Enforcing')  %}
haproxy_connect_any:
  selinux.boolean:
    - value: True
    - persist: True
    - require:
      - sls: /formulas/haproxy/install
{% endif %}

acme_certs:
  acme.cert:
    - name: {{ pillar['haproxy']['dashboard_domain'] }}
    - aliases:
      - {{ pillar['haproxy']['console_domain'] }}
      - {{ pillar['haproxy']['docs_domain'] }}
      - {{ pillar['haproxy']['guacamole_domain'] }}
      - {{ pillar['haproxy']['webssh2_domain'] }}
    - email: {{ pillar['haproxy']['acme_email'] }}
    - renew: 14
{% if salt['pillar.get']('development:test_certs', False) == True %}
    - test_cert: True
{% endif %}
{% if salt['pillar.get']('danos:enabled', False) == True %}
    - require:
      - danos: set haproxy group
      - danos: set haproxy static-mapping
{% endif %}

create_master_pem:
  cmd.run:
    - name: cat /etc/letsencrypt/live/{{ pillar['haproxy']['dashboard_domain'] }}/fullchain.pem /etc/letsencrypt/live/{{ pillar['haproxy']['dashboard_domain'] }}/privkey.pem > /etc/letsencrypt/live/{{ pillar['haproxy']['dashboard_domain'] }}/master.pem
    - creates: /etc/letsencrypt/live/{{ pillar['haproxy']['dashboard_domain'] }}/master.pem
    - require:
      - acme: acme_certs

/etc/haproxy/haproxy.cfg:
  file.managed:
    - source: salt://formulas/haproxy/files/haproxy.cfg
    - template: jinja
{% if salt['pillar.get']('syslog_url', False) == False %}
  {% for host, addresses in salt['mine.get']('role:graylog', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
    {% for address in addresses if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
    - context:
        syslog: {{ address }}:5514
    {% endfor %}
  {% endfor %}
{% endif %}
    - defaults:
{% if salt['pillar.get']('syslog_url', False) != False %}
        syslog: {{ pillar['syslog_url'] }}
{% else %}
        syslog: 127.0.0.1:5514
{% endif %}
        seamless_reload: stats socket /var/run/haproxy.sock mode 600 expose-fd listeners level user
        hostname: {{ grains['id'] }}
        management_ip_address: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
        dashboard_domain: {{ pillar['haproxy']['dashboard_domain'] }}
        console_domain:  {{ pillar['haproxy']['console_domain'] }}
        docs_domain:  {{ pillar['haproxy']['docs_domain'] }}
        guacamole_domain:  {{ pillar['haproxy']['guacamole_domain'] }}
        webssh2_domain:  {{ pillar['haproxy']['webssh2_domain'] }}


haproxy_service_watch:
  service.running:
    - name: haproxy
    - reload: true
    - watch:
      - file: /etc/haproxy/haproxy.cfg
