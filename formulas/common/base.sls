include:
  - formulas/common/syslog

{% set type = opts.id.split('-') %}
role:
  grains.present:
    - value: {{ type[0] }}

type:
  grains.present:
    - value: {{ type[0] }}

{% if grains['os_family'] == 'Debian' %}
  {% if opts.id.split('-')[0] not in ['cache', 'salt', 'pxe'] %}
  {% set cache_addresses_dict = salt['mine.get']('cache*','network.ip_addrs') %}
/etc/apt/apt.conf.d/02proxy:
  file.managed:
    - contents: |
  {% for host in cache_addresses_dict %}
        Acquire::http { Proxy "http://{{ cache_addresses_dict[host][0] }}:3142"; };
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

{{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}:
  host.only:
    - hostnames:
      - {{ grains['id'] }}
      - {{ grains['host'] }}

base_mine_update:
  module.run:
    - name: mine.update
