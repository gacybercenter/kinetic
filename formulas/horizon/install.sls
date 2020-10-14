include:
  - /formulas/common/base
  - /formulas/common/networking
  - /formulas/common/install
  - /formulas/common/openstack/repo

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
      - python3-sahara-dashboard
      - python3-manila-ui
      - git
      - build-essential
      - python3-dev
    - reload_modules: True

magnum_latest:
  git.latest:
    - name: https://opendev.org/openstack/magnum-ui.git
    - branch: stable/train
    - target: /usr/share/openstack-dashboard/magnum-ui/
    - force_clone: true

copy_magnum_panels:
  module.run:
    - name: file.copy
    - src: /usr/share/openstack-dashboard/magnum-ui/magnum_ui/enabled/
    - dst: /usr/share/openstack-dashboard/openstack_dashboard/local/enabled/
    - recurse: True
    - unless:
      - test -f /usr/share/openstack-dashboard/openstack_dashboard/local/enabled/_1370_project_container_infra_panel_group.py

magnum_ui_requirements:
  cmd.run:
    - name: pip3 install -r /usr/share/openstack-dashboard/magnum-ui/requirements.txt
    - onchanges:
      - git: magnum_latest

install_magnum_ui:
  cmd.run:
    - name: python3 setup.py install
    - cwd: /usr/share/openstack-dashboard/magnum-ui/
    - onchanges:
      - cmd: magnum_ui_requirements

{% elif grains['os_family'] == 'RedHat' %}

horizon_packages:
  pkg.installed:
    - pkgs:
      - python3-openstackclient
      - openstack-heat-ui
      - python3-pip
      - python3-setuptools
      - openstack-designate-ui
      - openstack-dashboard
      - openstack-magnum-ui
      - openstack-sahara-ui
      - openstack-manila-ui
      - gcc
      - git
      - platform-python-devel
    - reload_modules: True

{% endif %}

## zun-ui installation routine
zun_latest:
  git.latest:
    - name: https://opendev.org/openstack/zun-ui.git
    - branch: stable/ussuri
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

zun_ui_requirements:
  cmd.run:
    - name: pip3 install -r /usr/share/openstack-dashboard/zun-ui/requirements.txt
    - onchanges:
      - git: zun_latest

install_zun_ui:
  cmd.run:
    - name: python3 setup.py install
    - cwd: /usr/share/openstack-dashboard/zun-ui/
    - onchanges:
      - cmd: zun_ui_requirements

set_module_permissions:
  file.directory:
    - name: /usr/share/openstack-dashboard/openstack_dashboard/local/enabled
    - file_mode: 644
    - follow_symlinks: True
    - recurse:
      - mode
