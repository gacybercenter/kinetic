include:
  - /formulas/common/base
  - /formulas/common/networking
  - /formulas/common/install

{% if grains['os_family'] == 'Debian' %}

nodesource:
  pkgrepo.managed:
    - humanname: nodesoure node.js 12.x repo
    - name: deb https://deb.nodesource.com/node_12.x focal main
    - file: /etc/apt/sources.list.d/nodejs.12.list
    - key_url: https://deb.nodesource.com/gpgkey/nodesource.gpg.key

update_packages_node:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkgrepo: nodesource
    - dist_upgrade: True

webssh2_packages:
  pkg.installed:
    - pkgs:
      - nodejs
      - apache2
    - reload_modules: True

/var/www/html:
  file.directory:
    - makedirs: True

webssh_source:
  archive.extracted:
    - name: /var/www/html/webssh2
    - source: https://github.com/billchurch/webssh2/archive/0.3.0.tar.gz

{% elif grains['os_family'] == 'RedHat' %}

webssh2_packages:
  pkg.installed:
    - sources:
      - teleport: https://get.gravitational.com/teleport-4.3.5-1.x86_64.rpm

{% endif %}
