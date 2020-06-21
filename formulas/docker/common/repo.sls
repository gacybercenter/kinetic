{% if grains['os_family'] == 'Debian' %}

docker_repo:
  pkgrepo.managed:
    - humanname: docker
    - name: deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable
    - file: /etc/apt/sources.list.d/docker.list
    - key_url: https://download.docker.com/linux/ubuntu/gpg

update_packages_docker:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - docker_repo
    - dist_upgrade: True

{% elif grains['os_family'] == 'RedHat' %}

docker_repo:
  pkgrepo.managed:
    - name: docker
    - baseurl: https://download.docker.com/linux/centos/7/$basearch/stable/
    - file: /etc/yum.repos.d/docker.repo
    - gpgkey: https://download.docker.com/linux/centos/gpg

update_packages_docker:
  cmd.run:
    - name: salt-call pkg.upgrade setopt='best=False'
    - onchanges:
      - docker_repo

{% endif %}
