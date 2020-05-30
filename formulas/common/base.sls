include:
  - formulas/common/syslog

{% if opts.id not in ['salt', 'pxe'] %}
  {% set type = opts.id.split('-')[0] %}
{% else %}
  {% set type = opts.id %}
{% endif %}

/etc/salt/minion.d/transport.conf:
  file.managed:
    - contents: |
        transport: {{ pillar ['salt_transport'] }}

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
    {% set cache_addresses_dict = salt['mine.get']('cache*','network.ip_addrs') %}
/etc/apt/apt.conf.d/02proxy:
  file.managed:
    - contents: |
    {% for host in cache_addresses_dict %}
        Acquire::http { Proxy "http://{{ cache_addresses_dict[host][0] }}:3142"; };
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
    {% set cache_addresses_dict = salt['mine.get']('cache*','network.ip_addrs') %}
/etc/yum.conf:
  file.managed:
    - contents: |
        [main]
        cachedir=/var/cache/yum/$basearch/$releasever
        gpgcheck=1
        best=True
        installonly_limit=3
    {% for host in cache_addresses_dict %}
        proxy=http://{{ cache_addresses_dict[host][0] }}:3142
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
