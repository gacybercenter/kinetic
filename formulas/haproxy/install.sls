haproxy:
  pkg.installed

## Workaround for https://github.com/saltstack/salt/issues/56473
{% if grains['saltversion'] == '3000.3' %}
{% for patch in ["modules/acme.py", "states/acme.py"] %}
{{ grains['saltpath'] }}/{{ patch }}:
  file.managed:
    - source: https://raw.githubusercontent.com/saltstack/salt/20074df7c49aeeb3784087d7048bc981b948517a/salt/{{ patch }}
    - skip_verify: True
{% endfor %}
{% endif %}

{% if grains['os_family'] == 'Debian' %}

letsencrypt:
  pkg.installed

{% elif grains['os_family'] == 'RedHat' %}

certbot:
  pkg.installed

{% endif %}
