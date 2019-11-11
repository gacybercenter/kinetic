haproxy:
  pkg.installed


{% if grains['os_family'] == 'Debian' %}

letsencrypt:
  pkg.installed

{% elif grains['os_family'] == 'RedHat' %}

certbot:
  pkg.installed

{% endif %}
