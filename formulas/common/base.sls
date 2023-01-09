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

include:
  - /formulas/common/fluentd/repo

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

common_logging_install:
  pkg.installed:
    - name: td-agent
    - require:
      - sls: /formulas/common/ceph/repo

grok_plugin_install:
  cmd.run:
    - name: td-agent-gem install fluent-plugin-grok-parser
    - require:
      - pkg: common_logging_install
  {% endif %}
{% endif %}

td-agent_log_permissions:
  user.present:
    - name: td-agent
    - groups:
      - adm
      - root
      - www-data
    {% if grains['type'] in ['mysql', 'rabbitmq', 'bind', 'horizon', 'etcd', 'placment', 'designate', 'zun', 'glance', 'heat'] %}
      - {{ type }}
    {% endif %}
    {% if grains['type'] in ['memcached'] %}
      - memcache
    {% endif %}
    {% if grains['type'] in ['storage', 'volume', 'cephmon', 'swift'] %}
      - ceph
    {% endif %}
    {% if grains['type'] in ['nova', 'keystone', 'compute'] %}
      - keystone
    {% endif %}
    {% if grains['type'] in ['nova', 'compute'] %}
      - nova
    {% endif %}
    {% if grains['type'] in ['controller', 'compute'] %}
      - libvirt
    {% endif %}
    {% if grains['type'] in ['neutron', 'network', 'compute'] %}
      - neutron
    {% endif %}
    {% if grains['type'] in ['volume', 'cinder'] %}
      - cinder
    {% endif %}
    {% if grains['type'] in ['network', 'haproxy'] %}
      - haproxy
    {% endif %}
    - require:
      - pkg: common_logging_install

/etc/td-agent/td-agent.conf:
  file:
    - append
    - template: jinja
    - sources:
      - salt://formulas/common/fluentd/files/00-source-salt.conf
      - salt://formulas/common/fluentd/files/00-source-syslog.conf
    {% if grains['type'] in ['designate', 'nova', 'glance', 'heat', 'neutron', 'storage', 'keystone', 'volume', 'cephmon', 'cinder', 'placement', 'network', 'swift', 'compute'] %}
      - salt://formulas/common/fluentd/files/01-source-api.conf
      - salt://formulas/common/fluentd/files/01-source-ceph.conf
    {% endif %}
    {% if grains['type'] == 'haproxy' %}
      - salt://formulas/common/fluentd/files/01-source-haproxy.conf
    {% endif %}
    {% if grains['type'] in ['compute', 'network', 'neutron'] %}
      - salt://formulas/common/fluentd/files/01-source-openvswitch.conf
    {% endif %}
    {% if grains['type'] in ['keystone', 'horizon', 'cinder', 'placement', 'cache', 'pxe'] %}
      - salt://formulas/common/fluentd/files/01-source-wsgi.conf
    {% endif %}
    {% if grains['type'] == 'mysql' %}
      - salt://formulas/common/fluentd/files/01-source-mariadb.conf
    {% endif %}
    {% if grains['type'] == 'rabbitmq' %}
      - salt://formulas/common/fluentd/files/01-source-rabbitmq.conf
    {% endif %}
      - salt://formulas/common/fluentd/files/02-filter-transform.conf
    {% if grains['type'] in ['keystone', 'horizon', 'cinder', 'placement', 'cache', 'pxe'] %}
      - salt://formulas/common/fluentd/files/04-format-wsgi.conf
    {% endif %}
      - salt://formulas/common/fluentd/files/05-match-opensearch.conf
    - defaults:
        fluentd_logger: {{ pillar['fluentd']['record'] }}
        fluentd_password: {{ pillar['fluentd_password'] }}
        hostname: {{ grains['host'] }}
    {% if grains['type'] == 'salt' %}
        salt_service_log: /var/log/salt/master,/var/log/salt/minion
    {% else %}
        salt_service_log: /var/log/salt/minion
    {% endif %}
    {% if grains['type'] in ['designate', 'nova', 'glance', 'heat', 'neutron', 'storage', 'keystone', 'volume', 'cephmon', 'cinder', 'placement', 'network', 'swift', 'compute'] %}
        service: {{ type }}
        {% if grains['type'] in ['nova'] %}
        api_service_log: {% for service in ['nova', 'keystone'] %}/var/log/{{ service }}/*.log{% if not loop.last %},{% endif %}{% endfor %}
        {% elif grains['type'] in ['volume'] %}
        api_service_log: {% for service in ['cinder'] %}/var/log/{{ service }}/*.log{% if not loop.last %},{% endif %}{% endfor %}
        {% elif grains['type'] in ['network'] %}
        api_service_log: /var/log/neutron/*.log
        {% elif grains['type'] in 'compute' %}
        api_service_log: {% for service in ['keystone', 'neutron', 'nova'] %}/var/log/{{ service }}/*.log{% if not loop.last %},{% endif %}{% endfor %}
        {% else %}
        api_service_log: /var/log/{{ type }}/*.log
        {% endif %}
    {% elif grains['type'] == ['keystone', 'horizon', 'cinder', 'placement', 'cache', 'pxe'] %}
        service: {{ type }}
    {% elif grains['type'] == 'rabbitmq' %}
        service: {{ type }}
        log_hostname: {{ grains['host'] }}
    {% endif %}
    - require:
      - pkg: common_logging_install

td-agent:
  service.running:
    - watch:
      - /etc/td-agent/td-agent.conf
    - require:
      - pkg: common_logging_install
  {% endif %}
{% endif %}