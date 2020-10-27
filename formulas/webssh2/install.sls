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
    - reload_modules: True

webssh2_source:
  git.latest:
    - name: https://github.com/billchurch/webssh2.git
    - target: /var/www/html/
    - rev: 0.3.0

install_webssh2:
  cmd.run:
    - name: npm install --production && npm audit fix
    - cwd: /var/www/html/app
    - creates:
      - /var/www/html/app/node_modules

{% elif grains['os_family'] == 'RedHat' %}

webssh2_packages:
  pkg.installed:
    - sources:
      - teleport: https://get.gravitational.com/teleport-4.3.5-1.x86_64.rpm

{% endif %}
