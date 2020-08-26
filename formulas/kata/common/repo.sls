{% if grains['os_family'] == 'Debian' %}

kata_repo:
  pkgrepo.managed:
    - humanname: kata containers
    - name: deb https://download.opensuse.org/repositories/home:/katacontainers:/releases:/x86_64:/master/xUbuntu_20.04/ /
    - file: /etc/apt/sources.list.d/kata.list
    - key_url: https://download.opensuse.org/repositories/home:/katacontainers:/releases:/x86_64:/master/xUbuntu_16.04/Release.key
### Currently impacted by https://github.com/kata-containers/kata-containers/issues/545
### Delete this before merging to master, ok for testing
###    - gpgcheck: 0

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
    - baseurl: https://download.opensuse.org/repositories/home:/katacontainers:/releases:/$basearch:/master/CentOS_8/
    - file: /etc/yum.repos.d/kata.repo
    - gpgkey: https://download.opensuse.org/repositories/home:/katacontainers:/releases:/$basearch:/master/CentOS_8/repodata/repomd.xml.key

update_packages_kata:
  cmd.run:
    - name: salt-call pkg.upgrade setopt='best=False'
    - onchanges:
      - kata_repo

{% endif %}
