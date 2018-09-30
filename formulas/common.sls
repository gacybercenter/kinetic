{{ pillar['timezone'] }}:
  timezone.system:
    - utc: True

{% for key in pillar['authorized_keys'] %}
test:
  ssh_auth.present:
    - user: root
    - enc: foo
{% endfor %}
