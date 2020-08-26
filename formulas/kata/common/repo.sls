{% if grains['os_family'] == 'Debian' %}

## Even though its referencing the 16.04 key, its the same one.
## See https://github.com/kata-containers/kata-containers/issues/545 for rationale
## This can be safely changed to the 20.04 key for correctness once available
kata_repo:
  pkgrepo.managed:
    - humanname: kata containers
    - name: deb https://download.opensuse.org/repositories/home:/katacontainers:/releases:/x86_64:/master/xUbuntu_20.04/ /
    - file: /etc/apt/sources.list.d/kata.list
    - key_url: https://download.opensuse.org/repositories/home:/katacontainers:/releases:/x86_64:/master/xUbuntu_16.04/Release.key

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
