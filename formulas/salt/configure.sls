include:
  - /formulas/salt/install

/srv/salt:
  file.directory:
    - makedirs: true

mv /etc/salt/pki/master/minions_pre/pxe /etc/salt/pki/master/minions/pxe:
  cmd.run:
    - creates:
      - /etc/salt/pki/master/minions/pxe

/etc/salt/master.d/gitfs_pillar.conf:
  file.managed:
    - contents: |
        ext_pillar:
          - git:
            - {{ pillar['gitfs_pillar_configuration']['branch'] }} {{ pillar['gitfs_pillar_configuration']['url'] }}:
              - env: base
        ext_pillar_first: true
        pillar_gitfs_ssl_verify: True

/etc/salt/master.d/gitfs_remotes.conf:
  file.managed:
    - contents: |
        gitfs_remotes:
          - {{ pillar['gitfs_remote_configuration']['url'] }}:
            - saltenv:
              - base:
                - ref: {{ pillar['gitfs_remote_configuration']['branch'] }}
        gitfs_saltenv_whitelist:
          - base

{% for directive, contents in pillar.get('master-config', {}).items() %}
/etc/salt/master.d/{{ directive}}.conf:
  file.managed:
    - contents_pillar: master-config:{{ directive }}
{% endfor %}

/srv/dynamic_pillar:
  file.directory

{% for service in pillar['openstack_services'] %}
/srv/dynamic_pillar/{{ service }}-test.sls:
  file.managed:
    - source: salt://formulas/salt/files/openstack_service_template.sls
    - template: jinja
    - defaults:
        service: {{ service }}
        mysql_password: {{ salt['random.get_str']('64') }}
        service_password: {{ salt['random.get_str']('64') }}
{% if service == 'designate' %}
        extra_opts: |
            designate_rndc_key: |
                key "designate" {
                        algorithm hmac-sha512;
                        secret
                "{{ salt['random.get_str']('64') | base64_encode }}";
                };
{% elif service == 'neutron' %}
        extra_opts: |
            metadata_proxy_shared_secret: {{ salt['random.get_str']('64') }}
{% elif service == 'zun' %}
        extra_opts: |
            kuryr_service_password: {{ salt['random.get_str']('64') }}
{% else %}
        extra_opts: ''
{% endif %}
{% endfor %}

/srv/dynamic_pillar/mysql-test.sls:
  file.managed:
    - contents: |
        mysql:
          mysql_root_password: {{ salt['random.get_str']('64') }}

/srv/dynamic_pillar/rabbitmq-test.sls:
  file.managed:
    - contents: |
        rabbitmq:
          rabbitmq_password: {{ salt['random.get_str']('64') }}

/srv/dynamic_pillar/ceph-test.sls:
  file.managed:
    - contents: |
        ceph:
          fsid: {{ salt['random.get_str']('64') | uuid }}
          ceph-mon-keyring: |
            [mon.]
                 key = {{ salt['random.get_str']('30') | base64_encode }}
                 caps mon = "allow *"
            [client.admin]
                 key = {{ salt['random.get_str']('30') | base64_encode }}
                 auid = 0
                 caps mds = "allow *"
                 caps mgr = "allow *"
                 caps mon = "allow *"
                 caps osd = "allow *"
            [client.bootstrap-osd]
                 key = {{ salt['random.get_str']('30') | base64_encode }}
                 caps mon = "profile bootstrap-osd"
          ceph-client-admin-keyring: |
            [client.admin]
                 key = {{ salt['random.get_str']('30') | base64_encode }}
                 auid = 0
                 caps mds = "allow *"
                 caps mgr = "allow *"
                 caps mon = "allow *"
                 caps osd = "allow *"
          ceph-keyring: |
            [client.bootstrap-osd]
                 key = {{ salt['random.get_str']('30') | base64_encode }}
                 caps mon = "profile bootstrap-osd"
          ceph-client-images-keyring: |
            [client.images]
                 key = {{ salt['random.get_str']('30') | base64_encode }}
                 caps mon = "allow r"
                 caps osd = "allow class-read object_prefix rbd_children, allow rwx pool=images"
          ceph-client-volumes-keyring: |
            [client.volumes]
                 key = {{ salt['random.get_str']('30') | base64_encode }}
                 caps mon = "allow r"
                 caps osd = "allow class-read object_prefix rbd_children, allow rwx pool=volumes, allow rx pool=images"
          ceph-client-compute-keyring: |
            [client.compute]
                 key = {{ salt['random.get_str']('30') | base64_encode }}
                 caps mon = "allow r"
                 caps osd = "allow class-read object_prefix rbd_children, allow rwx pool=vms, allow rx pool=images"
          ceph-client-swift-keyring: |
            [client.swift]
                 key = {{ salt['random.get_str']('30') | base64_encode }}
                 caps mon = "allow rwx"
                 caps osd = "allow rwx"
          ceph-client-radosgw-keyring: |
            [client.radosgw]
                 key = {{ salt['random.get_str']('30') | base64_encode }}
                 caps mon = "allow rwx"
                 caps osd = "allow rwx"
          ceph-client-compute-key: {{ salt['random.get_str']('30') | base64_encode }}
          ceph-client-volumes-key: {{ salt['random.get_str']('30') | base64_encode }}
          volumes-uuid: {{ salt['random.get_str']('30') | uuid }}
          nova-uuid: {{ salt['random.get_str']('30') | uuid }}

/srv/dynamic_pillar/openstack-test.sls:
  file.managed:
    - contents: |
        openstack:
          admin_password: {{ salt['random.get_str']('64') }}

/srv/dynamic_pillar/top-test.sls:
  file.managed:
    - source: salt://formulas/salt/files/top.sls

/srv/dynamic_pillar/adminrc-test:
  file.managed:
    - contents: |
        #!/bin/bash
        export OS_USERNAME=admin
        export OS_PASSWORD={{ salt['pillar.get']('openstack:admin_password', 'TBD') }}
        export OS_USER_DOMAIN_NAME=Default
        export OS_PROJECT_NAME=admin
        export OS_PROJECT_DOMAIN_NAME=Default
        export OS_AUTH_URL={{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
        export OS_IDENTITY_API_VERSION=3

/etc/salt/master:
  file.managed:
    - contents: ''
    - contents_newline: False

salt-master:
  service.running:
    - watch:
      - file: /etc/salt/master
      - file: /etc/salt/master.d/*
