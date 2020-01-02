include:
  - formulas/openstack/common/repo

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
      - python2-ldap ## version agnostic
      - python2-openstackclient ## version agnostic
      - openldap-clients
      - httpd
      - mod_wsgi

{% endif %}
