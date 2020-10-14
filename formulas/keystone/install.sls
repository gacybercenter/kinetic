include:
  - /formulas/common/base
  - /formulas/common/networking
  - /formulas/common/install
  - /formulas/common/openstack/repo

{% if grains['os_family'] == 'Debian' %}

keystone_packages:
  pkg.installed:
    - pkgs:
      - keystone
      - python3-ldap
      - python3-ldappool
      - python3-openstackclient
      - ldap-utils
      - apache2
      - libapache2-mod-wsgi-py3

{% elif grains['os_family'] == 'RedHat' %}

keystone_packages:
  pkg.installed:
    - pkgs:
      - openstack-keystone
      - python3-ldap3 ## version agnostic
      - python3-openstackclient ## version agnostic
      - openldap-clients
      - httpd
      - python3-mod_wsgi

{% endif %}
