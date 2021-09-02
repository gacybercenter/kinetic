## Copyright 2018 Augusta University
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##    http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.

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
  {% if salt['pillar.get']('hosts:sahara:enabled', 'False') == True %}
      - python3-sahara-dashboard
  {% endif %}
  {% if salt['pillar.get']('hosts:magnum:enabled', 'False') == True %}
      - python3-manila-ui
  {% endif %}
      - python3-cffi
      - git
      - build-essential
      - python3-dev
    - reload_modules: True

  {% if salt['pillar.get']('hosts:magnum:enabled', 'False') == True %}
magnum_latest:
  git.latest:
    - name: https://opendev.org/openstack/magnum-ui.git
    - branch: stable/wallaby
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
  {% endif %}

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
  {% if salt['pillar.get']('hosts:magnum:enabled', 'False') == True %}
      - openstack-magnum-ui
  {% endif %}
  {% if salt['pillar.get']('hosts:sahara:enabled', 'False') == True %}
      - openstack-sahara-ui
  {% endif %}
  {% if salt['pillar.get']('hosts:manila:enabled', 'False') == True %}
      - openstack-manila-ui
  {% endif %}
      - gcc
      - git
      - platform-python-devel
    - reload_modules: True

{% endif %}

## zun-ui installation routine
zun_latest:
  git.latest:
    - name: https://opendev.org/openstack/zun-ui.git
    - branch: stable/wallaby
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
    - file_mode: "0644"
    - follow_symlinks: True
    - recurse:
      - mode
