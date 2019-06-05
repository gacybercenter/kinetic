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

/etc/salt/master:
  file.managed:
    - contents: ''
    - contents_newline: False

salt-master:
  service.running:
    - watch:
      - file: /etc/salt/master
      - file: /etc/salt/master.d/*
