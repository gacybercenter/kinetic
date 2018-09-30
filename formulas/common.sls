{{ pillar['timezone'] }}:
  timezone.system:
    - utc: True

{% for key, encoding in pillar.get('authorized_keys', {}).items() %}
{{ key }}:
  ssh_auth.present:
    - user: root
    - enc: {{ encoding }}
{% endfor %}
