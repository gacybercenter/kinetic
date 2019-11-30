include:
  - formulas/openstack/common/repo

{% if grains['os_family'] == 'Debian' %}

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
    - reload_modules: True

{% elif grains['os_family'] == 'RedHat' %}

horizon_packages:
  pkg.installed:
    - pkgs:
      - python2-openstackclient
      - openstack-heat-ui
      - python2-pip
      - python2-setuptools
      - openstack-designate-ui
      - openstack-dashboard
      - git
    - reload_modules: True

{% endif %}


## zun-ui installation routine
zun_latest:
  git.latest:
    - name: https://opendev.org/openstack/zun-ui.git
    - branch: stable/train
    - target: /usr/share/openstack-dashboard/zun-ui/
    - force_clone: true

copy_zun_panels:
  module.run:
    - name: file.copy
    - src: /usr/share/openstack-dashboard/zun-ui/zun_ui/enabled/
    - dst: /usr/share/openstack-dashboard/openstack_dashboard/local/enabled/
    - recurse: True
    - unless:
      - test -f /usr/share/openstack-dashboard/openstack_dashboard/local/enabled/_0330_cloud_shell.py

/usr/share/openstack-dashboard/openstack_dashboard/local/local_settings.d/_0330_cloud_shell_settings.py:
  file.managed:
    - source: salt://formulas/horizon/files/_0330_cloud_shell_settings.py
    - template: jinja
    - defaults:
        cloud_shell_image: {{ pillar['zun']['cloud_shell_image'] }}

{% if grains['os_family'] == 'Debian' %}

pip3 install -r /usr/share/openstack-dashboard/zun-ui/requirements.txt:
  cmd.run

installzun-ui:
  cmd.run:
    - name: python3 setup.py install
    - cwd: /usr/share/openstack-dashboard/zun-ui/

collect-static:
  cmd.run:
    - name: python3 manage.py collectstatic --noinput
    - cwd: /usr/share/openstack-dashboard/

compress-static:
  cmd.run:
    - name: python3 manage.py compress
    - cwd: /usr/share/openstack-dashboard/

{% elif grains['os_family'] == 'RedHat' %}

pip install -r /usr/share/openstack-dashboard/zun-ui/requirements.txt:
  cmd.run

installzun-ui:
  cmd.run:
    - name: python2 setup.py install
    - cwd: /usr/share/openstack-dashboard/zun-ui/

collect-static:
  cmd.run:
    - name: python2 manage.py collectstatic --noinput
    - cwd: /usr/share/openstack-dashboard/

compress-static:
  cmd.run:
    - name: python2 manage.py compress
    - cwd: /usr/share/openstack-dashboard/

{% endif %}
