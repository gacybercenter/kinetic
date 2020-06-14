haproxy:
  pkg.installed

## Workaround for https://github.com/saltstack/salt/issues/56473
## This fix was written for 2019.2 - there are master conflicts in 3000.3
# {% if grains['saltversion'] == '3000.3' %}
# {% for patch in ["modules/acme.py", "states/acme.py"] %}
# {{ grains['saltpath'] }}/{{ patch }}:
#  file.managed:
#    - source: https://raw.githubusercontent.com/saltstack/salt/20074df7c49aeeb3784087d7048bc981b948517a/salt/{{ patch }}
#    - skip_verify: True
# {% endfor %}
# {% endif %}

{% if grains['os_family'] == 'Debian' %}

letsencrypt:
  pkg.installed

{% elif grains['os_family'] == 'RedHat' %}

haproxy_packages:
  pkg.installed:
    - pkgs:
      - certbot
      - policycoreutils-python-utils
    - reload_modules: True

{% endif %}
