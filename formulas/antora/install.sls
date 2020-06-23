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

antora_packages:
  pkg.installed:
    - pkgs:
      - apt-transport-https
      - curl
      - lsb-release
      - gnupg
      - nodejs
      - apache2
    - reload_modules: True

{% elif grains['os_family'] == 'RedHat' %}

nodesource:
  pkgrepo.managed:
    - humanname: nodesoure node.js 12.x repo
    - name: nodesource
    - baseurl: https://rpm.nodesource.com/pub_12.x/el/8/x86_64/
    - file: /etc/yum.repos.d/nodesource.repo
    - gpgkey: https://rpm.nodesource.com/pub/el/NODESOURCE-GPG-SIGNING-KEY-EL

update_packages_nodesource:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkgrepo: nodesource

antora_packages:
  pkg.installed:
    - pkgs:
      - curl
      - gnupg2
      - nodejs
      - httpd
    - reload_modules: True

{% endif %}

install_antora:
  npm.installed:
    - pkgs:
      - "@antora/cli@2.3"
      - "@antora/site-generator-default@2.3"
