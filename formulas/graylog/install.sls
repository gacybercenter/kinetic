include:
  - /formulas/common/base
  - /formulas/common/networking
  - /formulas/common/install

{% if grains['os_family'] == 'Debian' %}

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
    - name: deb https://packages.graylog2.org/repo/debian/ stable 3.3
    - file: /etc/apt/sources.list.d/graylog.list
    - key_url: https://packages.graylog2.org/repo/debian/keyring.gpg

update_packages_graylog:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkgrepo: graylog_repo
    - dist_upgrade: True

{% elif grains['os_family'] == 'RedHat' %}

mongodb_repo:
  pkgrepo.managed:
    - name: mongodb
    - baseurl: https://repo.mongodb.org/yum/redhat/$releasever/mongodb-org/4.0/x86_64/
    - file: /etc/yum.repos.d/mongodb.repo
    - gpgkey: https://www.mongodb.org/static/pgp/server-4.0.asc

update_packages_mongo:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkgrepo: mongodb_repo

elasticsearch_repo:
  pkgrepo.managed:
    - name: elastic-6
    - baseurl: https://artifacts.elastic.co/packages/oss-6.x/yum
    - file: /etc/yum.repos.d/elastic-6.repo
    - gpgkey: https://artifacts.elastic.co/GPG-KEY-elasticsearch

update_packages_elastic:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkgrepo: elasticsearch_repo

graylog_repo:
  pkgrepo.managed:
    - name: graylog
    - baseurl: https://packages.graylog2.org/repo/el/stable/3.3/$basearch/
    - file: /etc/yum.repos.d/graylog.repo
    - gpgkey: https://packages.graylog2.org/repo/debian/pubkey.gpg

update_packages_graylog:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkgrepo: graylog_repo

{% endif %}

install_java:
  pkg.installed:
{% if grains['os_family'] == 'Debian' %}
    - name: openjdk-8-jre-headless
{% elif grains['os_family'] == 'RedHat' %}
    - name: java-1.8.0-openjdk-headless
{% endif %}
    - reload_modules: true
    - require_in: graylog_packages

graylog_packages:
  pkg.installed:
    - pkgs:
{% if grains['os_family'] == 'Debian' %}
      - apt-transport-https
      - uuid-runtime
{% elif grains['os_family'] == 'RedHat' %}
      - nmap-ncat
{% endif %}
      - mongodb-org
      - elasticsearch-oss
      - graylog-server
      - jq
    - reload_modules: True
