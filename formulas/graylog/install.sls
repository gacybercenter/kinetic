mongodb_repo:
  pkgrepo.managed:
    - humanname: MongoDB 4.0 repo
    - name: deb https://repo.mongodb.org/apt/ubuntu bionic/mongodb-org/4.0 multiverse
    - file: /etc/apt/sources.list.d/mongodb.4.list
    - keyid: E52529D4
    - keyserver: keyserver.ubuntu.com

update_packages_mongo:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkgrepo: mongodb_repo
    - dist_upgrade: True

elasticsearch_repo:
  pkgrepo.managed:
    - humanname: Elastic Search 6
    - name: deb https://artifacts.elastic.co/packages/oss-6.x/apt stable main
    - file: /etc/apt/sources.list.d/elastic-6.x.list
    - key_url: https://artifacts.elastic.co/GPG-KEY-elasticsearch

update_packages_elastic:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkgrepo: elasticsearch_repo
    - dist_upgrade: True

graylog_repo:
  pkgrepo.managed:
    - humanname: Graylog
    - name: deb https://packages.graylog2.org/repo/debian/ stable 3.1
    - file: /etc/apt/sources.list.d/graylog.list
    - key_url: https://packages.graylog2.org/repo/debian/keyring.gpg

update_packages_graylog:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkgrepo: graylog_repo
    - dist_upgrade: True


install_java:
  pkg.installed:
{% if grain['os_family'] == 'Debian' %}
    - name: openjdk-8-jre-headless
{% elif grain['os_family'] == 'RedHat' %}
    - name: java-1.8.0-openjdk-headless
{% endif %}    
    - reload_modules: true
    - require_in: graylog_packages

graylog_packages:
  pkg.installed:
    - pkgs:
      - apt-transport-https
      - uuid-runtime
      - pwgen
      - mongodb-org
      - elasticsearch-oss
      - graylog-server
      - jq
    - reload_modules: True
