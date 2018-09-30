{{ pillar['timezone'] }}:
  timezone.system:
    - utc: True

{% for key in pillar['authorized_keys'] %}
echo {{ key }}:
  ssh_auth.present:
    - user: root
    - enc: foo
{% endfor %}
