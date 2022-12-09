## Copyright 2018 Augusta University
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

{% set type = opts.id.split('-')[0] %}
{% set role = salt['pillar.get']('hosts:'+type+':role', type) %}

initial_module_sync:
  saltutil.sync_all:
    - refresh: True
    - unless:
      - fun: grains.has_value
        key: build_phase

build_phase:
  grains.present:
    - value: base
    - unless:
      - fun: grains.has_value
        key: build_phase

type:
  grains.present:
    - value: {{ type }}

role:
  grains.present:
    - value: {{ role }}

{{ pillar['timezone'] }}:
  timezone.system:
    - utc: True

{% if grains['os_family'] == 'Debian' %}
/etc/systemd/timesyncd.conf:
  file.managed:
    - source: salt://formulas/common/ntp/timesyncd.conf
    - template: jinja
    - defaults:
        ntp_server: {{ pillar['ntp']['ntp_server'] }}
        ntp_fallback: {{ pillar['ntp']['ntp_fallback'] }}
  cmd.wait:
    - name: timedatectl set-ntp true
{% endif %}

{% for key in pillar['authorized_keys'] %}
{{ key }}:
  ssh_auth.present:
    - user: root
    - enc: {{ pillar['authorized_keys'][ key ]['encoding'] }}
{% endfor %}

{% if opts.id not in ['salt', 'pxe'] %}
hosts_name_resolution:
  host.present:
    - ip: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
    - names:
      - {{ grains['id'] }}
      - {{ grains['host'] }}
    - clean: true
{% endif %}

/etc/rsyslog.d/10-syslog.conf:
  file.managed:
    - source: salt://formulas/common/syslog/files/10-syslog.conf
    - template: jinja
    - defaults:
        logger: 127.0.0.1:5514


{% if grains['os_family'] == 'Debian' %}
timesyncd:
  service.running:
    - name: systemd-timesyncd
    - enable: True
    - onchanges:
      - /etc/systemd/timesyncd.conf
{% endif %}

rsyslog:
  service.running:
    - watch:
      - /etc/rsyslog.d/10-syslog.conf

/etc/security/limits.d/90-ulimit-default.conf:
  file.managed:
    - source: salt://formulas/common/ulimit/90-ulimit-default.conf
    - user: root
    - group: root
    - mode: "0644"

# TODO(chateaulav): look at method for logic for dynamic opensearch
# node ip
{% if salt['pillar.get']('fluentd:enabled', False) == True %}
  {% if grains['os_family'] == 'Debian' %}
  
/etc/td-agent/td-agent.conf:
  file:
    - append
    - template: jinja
    - sources:
      - salt://formulas/common/fluentd/files/00-source-salt.conf
      - salt://formulas/common/fluentd/files/00-source-syslog.conf
    {% if grains['type'] in ['designate', 'nova', 'glance', 'heat', 'neutron', 'storage', 'keystone', 'volume', 'cephmon', 'cinder', 'placement', 'network', 'swift', 'compute'] %}
      - salt://formulas/common/fluentd/files/01-source-api.conf
    {% endif %}
    {% if grains['type'] in ['compute', 'network', 'neutron'] %}
      - salt://formulas/common/fluentd/files/01-source-openvswitch.conf
    {% endif %}
    {% if grains['type'] == 'compute' %}
      - salt://formulas/common/fluentd/files/01-source-libvirt.conf
    {% endif %}
    {% if grains['type'] in ['keystone', 'horizon', 'cinder', 'placement', 'cache', 'pxe'] %}
      - salt://formulas/common/fluentd/files/01-source-wsgi.conf
    {% endif %}
    {% if grains['type'] == 'mysql' %}
      - salt://formulas/common/fluentd/files/source-mariadb.conf
    {% endif %}
    {% if grains['type'] == 'rabbitmq' %}
      - salt://formulas/common/fluentd/files/source-rabbitmq.conf
    {% endif %}
      - salt://formulas/common/fluentd/files/02-filter-transform.conf
      - salt://formulas/common/fluentd/files/03-filter-rewrite.conf
      - salt://formulas/common/fluentd/files/04-format-apache.conf
      - salt://formulas/common/fluentd/files/04-format-wsgi.conf
      - salt://formulas/common/fluentd/files/05-match-opensearch.conf
    - defaults:
        fluentd_logger: {{ pillar['fluentd']['record'] }}
        fluentd_password: {{ pillar['fluentd_password'] }}
        hostname: {{ grains['host'] }}
    {% if grains['type'] in ['designate', 'nova', 'glance', 'heat', 'neutron', 'storage', 'keystone', 'volume', 'cephmon', 'cinder', 'placement', 'network', 'swift', 'compute'] %}
        service: {{ type }}
        {% if grains['type'] == 'storage' %}
        api_service_log: /var/log/ceph/*.log
        {% elif grains['type'] in 'nova' %}
        api_service_log: {% for service in ['nova', 'keystone'] %}/var/log/{{ service }}/*.log{% if not loop.last %},{% endif %}{% endfor %}
        {% elif grains['type'] in 'volume' %}
        api_service_log: {% for service in ['ceph', 'cinder'] %}/var/log/{{ service }}/*.log{% if not loop.last %},{% endif %}{% endfor %}
        {% elif grains['type'] in 'cephmon' %}
        api_service_log: /var/log/ceph/*.log
        {% elif grains['type'] in 'network' %}
        api_service_log: /var/log/neutron/*.log
        {% elif grains['type'] in 'swift' %}
        api_service_log: /var/log/ceph/*.log
        {% elif grains['type'] in 'compute' %}
        api_service_log: {% for service in ['ceph', 'keystone', 'neutron', 'nova'] %}/var/log/{{ service }}/*.log{% if not loop.last %},{% endif %}{% endfor %}
        {% else %}
        api_service_log: /var/log/{{ service }}/*.log
        {% endif %}

    {% elif grains['type'] == ['keystone', 'horizon', 'cinder', 'placement', 'cache', 'pxe'] %}
        service: {{ type }}
    {% elif grains['type'] == 'rabbitmq' %}
        service: {{ type }}
        log_hostname: {{ grains['host'] }}
    {% else %}
        service: {{ type }}
    {% endif %}

td-agent:
  service.running:
    - watch:
      - /etc/td-agent/td-agent.conf
  {% endif %}
{% endif %}