include:
  - formulas/common/syslog

sync_everything:
  saltutil.sync_all:
    - refresh: True

{% if opts.id not in ['salt', 'pxe'] %}
  {% set type = opts.id.split('-')[0] %}
{% else %}
  {% set type = opts.id %}
{% endif %}

type:
  grains.present:
    - value: {{ type }}

role:
  grains.present:
{% if pillar['types'][type] == 'physical' %}
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
  {% if type not in ['cache','salt','pxe'] %}
    {% for host, addresses in salt['mine.get']('role:cache', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
      {%- for address in addresses -%}
        {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
/etc/apt/apt.conf.d/02proxy:
  file.managed:
    - contents: |
        Acquire::http { Proxy "http://{{ address }}:3142"; };
        {% endif %}
      {% endfor %}
    {% endfor %}
  {% endif %}

  {% if salt['grains.get']('upgraded') != True %}

install_networkd:
  pkg.installed:
    - name: systemd-networkd

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
  {% if type not in ['cache','salt','pxe'] %}
    {% for host, addresses in salt['mine.get']('role:cache', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
      {%- for address in addresses -%}
        {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
/etc/yum.conf:
  file.managed:
    - contents: |
        [main]
        cachedir=/var/cache/yum/$basearch/$releasever
        gpgcheck=1
        best=True
        installonly_limit=3
        proxy=http://{{ address }}:3142
        {% endif %}
      {% endfor %}
    {% endfor %}
  {% endif %}

  {% if salt['grains.get']('upgraded') != True %}

install_networkd:
  pkg.installed:
    - name: systemd-networkd

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

cryptography:
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
