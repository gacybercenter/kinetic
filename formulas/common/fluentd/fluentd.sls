## Copyright 2020 Augusta University
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

{% if salt['pillar.get']('fluentd:enabled', False) == True %}
  {% if grains['os_family'] == 'Debian' %}

common_logging_install:
  pkg.installed:
    - name: td-agent
    - require:
      - sls: /formulas/common/fluentd/repo
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

grok_plugin_install:
  cmd.run:
    - name: td-agent-gem install fluent-plugin-grok-parser
    - require:
      - pkg: common_logging_install
    - unless:
      - td-agent-gem list | grep -q 'fluent-plugin-grok-parser'

td-agent_log_permissions:
  user.present:
    - name: td-agent
    - groups:
      - adm
      - root
      - www-data
    {% if type in ['mysql', 'rabbitmq', 'bind', 'horizon', 'etcd', 'placment', 'designate', 'zun', 'glance', 'heat'] %}
      - {{ type }}
    {% endif %}
    {% if type in ['memcached'] %}
      - memcache
    {% endif %}
    {% if type in ['storage', 'volume', 'cephmon', 'swift'] %}
      - ceph
    {% endif %}
    {% if type in ['nova', 'keystone', 'compute'] %}
      - keystone
    {% endif %}
    {% if type in ['nova', 'compute'] %}
      - nova
    {% endif %}
    {% if type in ['controller', 'compute'] %}
      - libvirt
    {% endif %}
    {% if type in ['neutron', 'network', 'compute'] %}
      - neutron
    {% endif %}
    {% if type in ['volume', 'cinder'] %}
      - cinder
    {% endif %}
    {% if type in ['network', 'haproxy'] %}
      - haproxy
    {% endif %}
    - require:
      - pkg: common_logging_install

td_agent_conf:
  file.managed:
    - name: /etc/td-agent/td-agent.conf
    - source: salt://formulas/common/fluentd/files/td-agent.conf
    - require:
      - pkg: common_logging_install
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

/etc/td-agent/td-agent.conf:
  file:
    - append
    - template: jinja
    - sources:
      - salt://formulas/common/fluentd/files/00-source-salt.conf
      - salt://formulas/common/fluentd/files/00-source-syslog.conf
    {% if type in ['designate', 'nova', 'glance', 'heat', 'neutron', 'storage', 'keystone', 'volume', 'cephmon', 'cinder', 'placement', 'network', 'swift', 'compute'] %}
      - salt://formulas/common/fluentd/files/01-source-api.conf
      - salt://formulas/common/fluentd/files/01-source-ceph.conf
    {% endif %}
    {% if type == 'haproxy' %}
      - salt://formulas/common/fluentd/files/01-source-haproxy.conf
    {% endif %}
    {% if type in ['compute', 'network', 'neutron'] %}
      - salt://formulas/common/fluentd/files/01-source-openvswitch.conf
    {% endif %}
    {% if type in ['keystone', 'horizon', 'cinder', 'placement', 'cache', 'pxe'] %}
      - salt://formulas/common/fluentd/files/01-source-wsgi.conf
    {% endif %}
    {% if type == 'mysql' %}
      - salt://formulas/common/fluentd/files/01-source-mariadb.conf
    {% endif %}
    {% if type == 'rabbitmq' %}
      - salt://formulas/common/fluentd/files/01-source-rabbitmq.conf
    {% endif %}
      - salt://formulas/common/fluentd/files/02-filter-transform.conf
    {% if type in ['keystone', 'horizon', 'cinder', 'placement', 'cache', 'pxe'] %}
      - salt://formulas/common/fluentd/files/04-format-wsgi.conf
    {% endif %}
      - salt://formulas/common/fluentd/files/05-match-opensearch.conf
    - defaults:
        fluentd_logger: {{ pillar['fluentd']['record'] }}
        fluentd_password: {{ pillar['fluentd_password'] }}
        hostname: {{ grains['host'] }}
        environment: {{ pillar['haproxy']['group'] }}
    {% if type == 'salt' %}
        salt_service_log: /var/log/salt/master,/var/log/salt/minion
    {% else %}
        salt_service_log: /var/log/salt/minion
    {% endif %}
    {% if type in ['designate', 'nova', 'glance', 'heat', 'neutron', 'storage', 'keystone', 'volume', 'cephmon', 'cinder', 'placement', 'network', 'swift', 'compute'] %}
        service: {{ type }}
        {% if type in ['nova'] %}
        api_service_log: {% for service in ['nova', 'keystone'] %}/var/log/{{ service }}/*.log{% if not loop.last %},{% endif %}{% endfor %}
        {% elif type in ['volume'] %}
        api_service_log: {% for service in ['cinder'] %}/var/log/{{ service }}/*.log{% if not loop.last %},{% endif %}{% endfor %}
        {% elif type in ['network'] %}
        api_service_log: /var/log/neutron/*.log
        {% elif type in 'compute' %}
        api_service_log: {% for service in ['keystone', 'neutron', 'nova'] %}/var/log/{{ service }}/*.log{% if not loop.last %},{% endif %}{% endfor %}
        {% else %}
        api_service_log: /var/log/{{ type }}/*.log
        {% endif %}
    {% elif type == ['keystone', 'horizon', 'cinder', 'placement', 'cache', 'pxe'] %}
        service: {{ type }}
    {% elif type == 'rabbitmq' %}
        service: {{ type }}
        log_hostname: {{ grains['host'] }}
    {% endif %}
    - require:
      - pkg: common_logging_install
      - file: td_agent_conf
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

td-agent:
  service.running:
    - watch:
      - /etc/td-agent/td-agent.conf
    - require:
      - pkg: common_logging_install
      - file: /etc/td-agent/td-agent.conf
  {% endif %}
{% endif %}