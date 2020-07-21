include:
  - formulas/common/syslog

initial_module_sync:
  saltutil.sync_all:
    - refresh: True
    - unless:
      - salt-call saltutil.list_extmods | grep -q 'redfish\|generate\|fernet\|address\|danos'

{% if opts.id not in ['salt', 'pxe'] %}
  {% set type = opts.id.split('-')[0] %}
{% else %}
  {% set type = opts.id %}
{% endif %}

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
{% if pillar['types'][type]['style'] == 'physical' %}
    - value: {{ pillar['hosts'][type]['role'] }}
{% else %}
    - value: {{ type }}
{% endif %}

{% if type in ['salt','pxe'] %}
ifwatch:
  grains.present:
    - value:
      - eth0
{% endif %}

{% if grains['os_family'] == 'Debian' %}
  {% if (type not in ['cache','salt','pxe'] and salt['mine.get']('role:cache', 'network.ip_addrs', tgt_type='grain')|length != 0) %}
    {% for address in salt['mine.get']('role:cache', 'network.ip_addrs', tgt_type='grain') | dictsort() | random() | last ()%}
      {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
/etc/apt/apt.conf.d/02proxy:
  file.managed:
    - contents: |
        Acquire::http { Proxy "http://{{ address }}:3142"; };
      {% endif %}
    {% endfor %}
  {% endif %}

  {% if salt['grains.get']('upgraded') != True %}

update_all:
  pkg.uptodate:
    - refresh: true
    - dist_upgrade: True

upgraded:
  grains.present:
    - value: True
    - require:
      - update_all

  {% endif %}

{% elif grains['os_family'] == 'RedHat' %}
  {% if (type not in ['cache','salt','pxe'] and salt['mine.get']('role:cache', 'network.ip_addrs', tgt_type='grain')|length != 0) %}
    {% for address in salt['mine.get']('role:cache', 'network.ip_addrs', tgt_type='grain') | dictsort() | random() | last ()%}
      {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
/etc/yum.conf:
  file.managed:
    - contents: |
        [main]
        gpgcheck=1
        installonly_limit=3
        clean_requirements_on_remove=True
        best=True
        skip_if_unavailable=False
        proxy=http://{{ address }}:3142
      {% endif %}
    {% endfor %}
  {% endif %}

  {% if salt['grains.get']('upgraded') != True %}

install_networkd:
  pkg.installed:
    - name: systemd-networkd

firewalld:
  pkg.removed

update_all:
  pkg.uptodate:
    - refresh: true

upgraded:
  grains.present:
    - value: True
    - require:
      - update_all

  {% endif %}
{% endif %}

install_pip:
  pkg.installed:
    - pkgs:
      - python3-pip
    - reload_modules: True

pyroute2:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - require:
      - install_pip
    - reload_modules: True

{{ pillar['timezone'] }}:
  timezone.system:
    - utc: True

{% for key in pillar['authorized_keys'] %}
{{ key }}:
  ssh_auth.present:
    - user: root
    - enc: {{ pillar['authorized_keys'][ key ]['encoding'] }}
{% endfor %}

{% if opts.id not in ['salt', 'pxe'] %}
{{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}:
  host.only:
    - hostnames:
      - {{ grains['id'] }}
      - {{ grains['host'] }}
{% endif %}
