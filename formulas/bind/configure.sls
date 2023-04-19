## Copyright 2019 Augusta University
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##    http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.

include:
  - /formulas/{{ grains['role'] }}/install
  - /formulas/common/fluentd/fluentd

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}

{% if grains['spawning'] == 0 %}

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

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
    - mode: "0640"
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
