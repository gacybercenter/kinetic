uca:
  pkgrepo.managed:
    - humanname: Ubuntu Cloud Archive - train
    - name: deb http://ubuntu-cloud.archive.canonical.com/ubuntu bionic-updates/train main
    - file: /etc/apt/sources.list.d/cloudarchive-train.list
    - keyid: ECD76E3E
    - keyserver: keyserver.ubuntu.com

update_packages_uca:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkgrepo: uca
    - dist_upgrade: True

horizon_packages:
  pkg.installed:
    - pkgs:
      - python3-openstackclient
      - python3-heat-dashboard
      - python3-pip
      - python3-setuptools
      - python3-designate-dashboard
      - openstack-dashboard
      - git

{% if salt['pillar.get']('horizon:theme:url', False) != False %}
install_theme:
  archive.extracted:
    - name: /usr/share/openstack-dashboard/openstack_dashboard/themes/
    - source: {{ salt['pillar.get']('horizon:theme:url') }}
{% endif %}
