include:
  - formulas/common/syslog

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

install_pip:
  pkg.installed:
    - pkgs:
      - python3-pip
    - reload_modules: True

pyroute2:
  pip.installed:
    - require:
      - install_pip
    - reload_modules: True

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
/etc/apt/apt.conf.d/02proxy:
  file.managed:
    - contents: |
        [main]
        cachedir=/var/cache/yum/$basearch/$releasever
        keepcache=0
        debuglevel=2
        logfile=/var/log/yum.log
        exactarch=1
        obsoletes=1
        gpgcheck=1
        plugins=1
        installonly_limit=5
        bugtracker_url=http://bugs.centos.org/set_project.php?project_id=23&ref=http://bugs.centos.org/bug_report_page.php?category=yum
        distroverpkg=centos-release
    {% for host in cache_addresses_dict %}
        proxy=http://{{ cache_addresses_dict[host][0] }}:3142
    {% endfor %}
  {% endif %}

  {% if salt['grains.get']('upgraded') != True %}
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
