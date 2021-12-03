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

include:
  - /formulas/{{ grains['role'] }}/install

{% import 'formulas/common/macros/constructor.sls' as constructor with context %}

/srv/salt:
  file.directory:
    - makedirs: true

/srv/addresses/addresses.db:
  file.managed:
    - replace: False
    - makedirs: True

addresses:
  sqlite3.table_present:
    - db: /srv/addresses/addresses.db
    - schema:
      - address TEXT UNIQUE
      - network TEXT
      - host TEXT
    - require:
      - file: /srv/addresses/addresses.db

{% for network in ['sfe', 'sbe', 'private'] %}
  {% for address in pillar['networking']['subnets'][network] | network_hosts %}
address_population_{{ address }}:
  sqlite3.row_present:
    - db: /srv/addresses/addresses.db
    - table: addresses
    - where_sql: address='{{ address }}'
    - data:
        address: {{ address }}
        network: {{ network }}
    - update: True
    - require:
      - sqlite3: addresses
  {% endfor %}
{% endfor %}

/srv/runners:
  file.directory:
    - makedirs: True

/srv/runners/needs.py:
  file.managed:
    - source: salt://_runners/needs.py

create_api_cert:
  cmd.run:
    - name: "salt-call --local tls.create_self_signed_cert"
    - creates:
      - /etc/pki/tls/certs/localhost.crt
      - /etc/pki/tls/certs/localhost.key

api:
  user.present:
    - password: {{ salt['pillar.get']('api:user_password', 'TBD') }}
    - hash_password: True

/etc/salt/master.d/gitfs_pillar.conf:
  file.managed:
    - contents: |
        ext_pillar:
          - git:
            - {{ pillar['kinetic_pillar_configuration']['branch'] }} {{ pillar['kinetic_pillar_configuration']['url'] }}:
              - env: base
        ext_pillar_first: False
        pillar_gitfs_ssl_verify: True

/etc/salt/master.d/gitfs_remotes.conf:
  file.managed:
    - contents: |
        gitfs_remotes:
          - {{ pillar['kinetic_remote_configuration']['url'] }}:
            - saltenv:
              - base:
                - ref: {{ pillar['kinetic_remote_configuration']['branch'] }}
{% for remote, config in pillar.get('gitfs_other_configurations', {}).items() %}
          - {{ pillar['gitfs_other_configurations'][remote]['url'] }}:
            - saltenv:
              - base:
                - ref: {{ pillar['gitfs_other_configurations'][remote]['branch'] }}
{% endfor %}
        gitfs_saltenv_whitelist:
          - base

{% for directive, contents in pillar.get('master-config', {}).items() %}
/etc/salt/master.d/{{ directive }}.conf:
  file.managed:
    - contents_pillar: master-config:{{ directive }}
{% endfor %}

/srv/dynamic_pillar:
  file.directory

/srv/dynamic_pillar/openstack_services.sls:
  file.managed:
    - source: salt://formulas/salt/files/openstack_services.sls

/srv/dynamic_pillar/integrated_services.sls:
  file.managed:
    - source: salt://formulas/salt/files/integrated_services.sls

{% for service in salt['pillar.get']('openstack_services', {}) %}
/srv/dynamic_pillar/{{ service }}.sls:
  file.managed:
    - source: salt://formulas/salt/files/openstack_service_template.sls
    - template: jinja
    - replace: false
    - require:
      - file: /srv/dynamic_pillar/openstack_services.sls
    - defaults:
        service: {{ service }}
        mysql_password: {{ salt['random.get_str']('64', punctuation=False) }}
        service_password: {{ salt['random.get_str']('64', punctuation=False) }}
{% if service == 'designate' %}
        extra_opts: |
            designate_rndc_key: |
                key "designate" {
                        algorithm hmac-sha512;
                        secret
                "{{ salt['random.get_str']('64', punctuation=False) | base64_encode }}";
                };
{% elif service == 'neutron' %}
        extra_opts: |
            metadata_proxy_shared_secret: {{ salt['random.get_str']('64', punctuation=False) }}
{% elif service == 'zun' %}
        extra_opts: |
            kuryr_service_password: {{ salt['random.get_str']('64', punctuation=False) }}
{% elif service == 'barbican' %}
        extra_opts: |
            simplecrypto_key: {{ salt['random.get_str']('32') | base64_encode }}
{% elif service == 'keystone' %}
        extra_opts: |
            fernet_primary: {{ salt['fernet.make_key']() }}
              fernet_secondary: {{ salt['fernet.make_key']() }}
{% else %}
        extra_opts: ''
{% endif %}
{% endfor %}

/srv/dynamic_pillar/horizon.sls:
  file.managed:
    - replace: false
    - contents: |
        horizon:
          horizon_secret_key: {{ salt['random.get_str']('64', punctuation=False) }}

/srv/dynamic_pillar/mysql.sls:
  file.managed:
    - replace: false
    - contents: |
        mysql:
          mysql_root_password: {{ salt['random.get_str']('64', punctuation=False) }}
          wsrep_cluster_name: {{ salt['random.get_str']('32') }}

/srv/dynamic_pillar/rabbitmq.sls:
  file.managed:
    - replace: false
    - contents: |
        rabbitmq:
          rabbitmq_password: {{ salt['random.get_str']('64', punctuation=False) }}
          erlang_cookie: {{ salt['generate.erlang_cookie'](20) }}

/srv/dynamic_pillar/etcd.sls:
  file.managed:
    - replace: false
    - contents: |
        etcd:
          etcd_cluster_token: {{ salt['random.get_str']('64', punctuation=False) }}

{% set graylog_password = salt['random.get_str']('64', punctuation=False) %}
/srv/dynamic_pillar/graylog.sls:
  file.managed:
    - replace: false
    - contents: |
        graylog:
          graylog_password: {{ graylog_password }}
          graylog_password_sha2: {{ graylog_password | sha256 }}

{% set adminkey = salt['generate.cephx_key']() %}
{% set volumeskey = salt['generate.cephx_key']() %}
{% set computekey = salt['generate.cephx_key']() %}
{% set crashkey = salt['generate.cephx_key']() %}
{% set osdkey = salt['generate.cephx_key']() %}

/srv/dynamic_pillar/ceph.sls:
  file.managed:
    - replace: false
    - contents: |
        ceph:
          fsid: {{ salt['random.get_str']('64', punctuation=False) | uuid }}
          ceph-mon-keyring: |
            [mon.]
                 key = {{ salt['generate.cephx_key']() }}
                 caps mon = "allow *"
            [client.admin]
                 key = {{ adminkey }}
                 auid = 0
                 caps mds = "allow *"
                 caps mgr = "allow *"
                 caps mon = "allow *"
                 caps osd = "allow *"
            [client.bootstrap-osd]
                 key = {{ osdkey }}
                 caps mon = "profile bootstrap-osd"
          ceph-client-admin-keyring: |
            [client.admin]
                 key = {{ adminkey }}
                 auid = 0
                 caps mds = "allow *"
                 caps mgr = "allow *"
                 caps mon = "allow *"
                 caps osd = "allow *"
          ceph-keyring: |
            [client.bootstrap-osd]
                 key = {{ osdkey }}
                 caps mon = "profile bootstrap-osd"
          ceph-client-images-keyring: |
            [client.images]
                 key = {{ salt['generate.cephx_key']() }}
                 caps mon = "allow r, allow command \"osd blacklist\""
                 caps osd = "allow class-read object_prefix rbd_children, allow rwx pool=images"
          ceph-client-volumes-keyring: |
            [client.volumes]
                 key = {{ volumeskey }}
                 caps mon = "allow r, allow command \"osd blacklist\""
                 caps osd = "allow class-read object_prefix rbd_children, allow rwx pool=volumes, allow rx pool=images"
          ceph-client-compute-keyring: |
            [client.compute]
                 key = {{ computekey }}
                 caps mon = "allow r, allow command \"osd blacklist\""
                 caps osd = "allow class-read object_prefix rbd_children, allow rwx pool=vms, allow rx pool=images"
          ceph-client-crash-keyring: |
            [client.crash]
                key = {{ crashkey }}
                caps mon = "profile crash"
                caps mgr = "profile crash"
          ceph-client-compute-key: {{ computekey }}
          ceph-client-volumes-key: {{ volumeskey }}
          volumes-uuid: {{ salt['random.get_str']('30') | uuid }}
          nova-uuid: {{ salt['random.get_str']('30') | uuid }}

/srv/dynamic_pillar/openstack.sls:
  file.managed:
    - replace: false
    - contents: |
        openstack:
          admin_password: {{ salt['random.get_str']('64', punctuation=False) }}

/srv/dynamic_pillar/api.sls:
  file.managed:
    - replace: false
    - contents: |
        api:
          user_password: {{ salt['random.get_str']('64', punctuation=False) }}

/srv/dynamic_pillar/cache.sls:
  file.managed:
    - replace: false
    - contents: |
        cache:
          maintenance_password: {{ salt['random.get_str']('64', punctuation=False) }}

/srv/dynamic_pillar/guacamole.sls:
  file.managed:
    - replace: false
    - contents: |
        guacamole:
          guacamole_mysql_password: {{ salt['random.get_str']('64', punctuation=False) }}
          guacadmin_password: {{ salt['random.get_str']('16') }}

/srv/dynamic_pillar/top.sls:
  file.managed:
    - source: salt://formulas/salt/files/top.sls
    - require:
      - file: /srv/dynamic_pillar/api.sls

/srv/dynamic_pillar/adminrc:
  file.managed:
    - contents: |
        #!/bin/bash
        export OS_USERNAME=admin
        export OS_PASSWORD={{ salt['pillar.get']('openstack:admin_password', 'TBD') }}
        export OS_USER_DOMAIN_NAME=Default
        export OS_PROJECT_NAME=admin
        export OS_PROJECT_DOMAIN_NAME=Default
        export OS_AUTH_URL={{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='internal') }}
        export OS_IDENTITY_API_VERSION=3

/srv/dynamic_pillar/adminrc.ps1:
  file.managed:
    - contents: |
        $env:OS_USERNAME = "admin"
        $env:OS_PASSWORD = "{{ salt['pillar.get']('openstack:admin_password', 'TBD') }}"
        $env:OS_USER_DOMAIN_NAME = "Default"
        $env:OS_PROJECT_NAME = "admin"
        $env:OS_PROJECT_DOMAIN_NAME = "Default"
        $env:OS_AUTH_URL = "{{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='internal') }}"
        $env:OS_IDENTITY_API_VERSION = "3"

/srv/dynamic_pillar/deps.sls:
  file.managed:
    - source: salt://formulas/salt/files/deps.sls
    - template: jinja
    - defaults:
{% if pillar['neutron']['backend'] == 'networking-ovn' %}
      ovsdb: "ovsdb: configure"
{% else %}
      ovsdb: ""
{% endif %}

/etc/salt/master:
  file.managed:
    - contents: ''
    - contents_newline: False

salt-api_service:
  service.running:
    - name: salt-api
    - enable: True
    - watch:
      - file: /etc/salt/master
      - file: /etc/salt/master.d/*

build_phase_final:
  grains.present:
    - name: build_phase
    - value: configure

salt-master_watch:
  cmd.run:
    - name: 'salt-call service.restart salt-master'
    - bg: True
    - onchanges:
      - file: /etc/salt/master
      - file: /etc/salt/master.d/*
    - order: last
