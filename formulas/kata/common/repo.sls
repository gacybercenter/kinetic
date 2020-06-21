{% if grains['os_family'] == 'Debian' %}

kata_repo:
  pkgrepo.managed:
    - humanname: kata containers
    - name: deb http://download.opensuse.org/repositories/home:/katacontainers:/releases:/x86_64:/master/xUbuntu_18.04/ /
    - file: /etc/apt/sources.list.d/kata.list
    - key_url: http://download.opensuse.org/repositories/home:/katacontainers:/releases:/x86_64:/master/xUbuntu_18.04/Release.key

update_packages_kata:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - kata_repo
    - dist_upgrade: True

{% elif grains['os_family'] == 'RedHat' %}

kata_repo:
  pkgrepo.managed:
    - name: kata
    - baseurl: http://download.opensuse.org/repositories/home:/katacontainers:/releases:/$basearch:/master/CentOS_7/
    - file: /etc/yum.repos.d/kata.repo
    - gpgkey: http://download.opensuse.org/repositories/home:/katacontainers:/releases:/$basearch:/master/CentOS_7/repodata/repomd.xml.key

update_packages_kata:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - kata_repo

{% endif %}
