{% set type = opts.id.split('-') %}
role:
  grains.present:
    - value: {{ pillar['hosts'][type]['role'] }}

{% if salt['grains.get']('os') != True %}
{% if grains['os_family'] == 'Debian' %}

update_all:
  pkg.uptodate:
    - refresh: true
    - dist_upgrade: True

upgraded:
  grains.present:
    - value: True
    - require:
      - update_all

{% elif grains['os_family'] == 'RedHat' %}

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

{{ grains['ipv4'][0] }}:
  host.only:
    - hostnames:
      - {{ grains['id'] }}
      - {{ grains['host'] }}
