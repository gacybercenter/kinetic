{% if grains['os_family'] == 'Debian' %}
apache2:
  pkg.installed

{% elif grains['os_family'] == 'RedHat' %}

httpd:
  pkg.installed
{% endif %}

apt-cacher-ng:
  pkg.installed
