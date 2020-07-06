{% if grains['os_family'] == 'Debian' %}

frr_repo:
  pkgrepo.managed:
    - humanname: frr-stable
    - name: deb https://deb.frrouting.org/frr focal frr-stable
    - file: /etc/apt/sources.list.d/frr-stable.list
    - key_url: https://deb.frrouting.org/frr/keys.asc

update_packages_frr:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - frr_repo
    - dist_upgrade: True

{% elif grains['os_family'] == 'RedHat' %}

frr_repo:
  pkgrepo.managed:
    - name: frr
    - baseurl: https://rpm.frrouting.org/repo/el8/frr
    - file: /etc/yum.repos.d/frr.repo
    - gpgkey: salt://formulas/frr/common/files/frr_rpm.gpg

frr_extras_repo:
  pkgrepo.managed:
    - name: frr_extras
    - baseurl: https://rpm.frrouting.org/repo/el8/extras
    - file: /etc/yum.repos.d/frr_extas.repo
    - gpgkey: salt://formulas/frr/common/files/frr_rpm.gpg

update_packages_frr:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkgrepo: frr_repo
      - pkgrepo: frr_extras_repo

{% endif %}
