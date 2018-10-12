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

{% set type = opts.id.split('-') %}

type:
  grains.present:
    - value: {{ type[0] }}
