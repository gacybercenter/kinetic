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
      - python3-sahara-dashboard
      - python3-manila-ui
      - git
      - build-essential
      - python3-dev
    - reload_modules: True

# magnum_latest:
#   git.latest:
#     - name: https://opendev.org/openstack/magnum-ui.git
#     - branch: stable/train
#     - target: /usr/share/openstack-dashboard/magnum-ui/
#     - force_clone: true
#
# copy_magnum_panels:
#   module.run:
#     - name: file.copy
#     - src: /usr/share/openstack-dashboard/magnum-ui/magnum_ui/enabled/
#     - dst: /usr/share/openstack-dashboard/openstack_dashboard/local/enabled/
#     - recurse: True
#     - unless:
#       - test -f /usr/share/openstack-dashboard/openstack_dashboard/local/enabled/_1370_project_container_infra_panel_group.py
#
# magnum_ui_requirements:
#   cmd.run:
#     - name: pip3 install -r /usr/share/openstack-dashboard/magnum-ui/requirements.txt
#     - onchanges:
#       - git: magnum_latest
#
# install_magnum_ui:
#   cmd.run:
#     - name: python3 setup.py install
#     - cwd: /usr/share/openstack-dashboard/magnum-ui/
#     - onchanges:
#       - cmd: magnum_ui_requirements
#
# collect-static-magnum:
#   cmd.run:
#     - name: python3 manage.py collectstatic --noinput
#     - cwd: /usr/share/openstack-dashboard/
#     - onchanges:
#       - cmd: install_magnum_ui
#
# compress-static-magnum:
#   cmd.run:
#     - name: python3 manage.py compress
#     - cwd: /usr/share/openstack-dashboard/
#     - onchanges:
#       - cmd: collect-static-magnum

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
      - openstack-magnum-ui
      - openstack-sahara-ui
      - openstack-manila-ui
      - gcc
      - git
      - python-devel
      - python3-devel
    - reload_modules: True

{% endif %}


# ## zun-ui installation routine
#
# zun_latest:
#   git.latest:
#     - name: https://opendev.org/openstack/zun-ui.git
#     - branch: stable/train
#     - target: /usr/share/openstack-dashboard/zun-ui/
#     - force_clone: true
#
# copy_zun_panels:
#   module.run:
#     - name: file.copy
#     - src: /usr/share/openstack-dashboard/zun-ui/zun_ui/enabled/
#     - dst: /usr/share/openstack-dashboard/openstack_dashboard/local/enabled/
#     - recurse: True
#     - unless:
#       - test -f /usr/share/openstack-dashboard/openstack_dashboard/local/enabled/_0330_cloud_shell.py
#
# /usr/share/openstack-dashboard/openstack_dashboard/local/local_settings.d/_0330_cloud_shell_settings.py:
#   file.managed:
#     - source: salt://formulas/horizon/files/_0330_cloud_shell_settings.py
#     - template: jinja
#     - defaults:
#         cloud_shell_image: {{ pillar['zun']['cloud_shell_image'] }}
#
# {% if grains['os_family'] == 'Debian' %}
#
# zun_ui_requirements:
#   cmd.run:
#     - name: pip3 install -r /usr/share/openstack-dashboard/zun-ui/requirements.txt
#     - onchanges:
#       - git: zun_latest
#
# install_zun_ui:
#   cmd.run:
#     - name: python3 setup.py install
#     - cwd: /usr/share/openstack-dashboard/zun-ui/
#     - onchanges:
#       - cmd: zun_ui_requirements
#
# collect-static-zun:
#   cmd.run:
#     - name: python3 manage.py collectstatic --noinput
#     - cwd: /usr/share/openstack-dashboard/
#     - onchanges:
#       - cmd: install_zun_ui
#
# compress-static-zun:
#   cmd.run:
#     - name: python3 manage.py compress
#     - cwd: /usr/share/openstack-dashboard/
#     - onchanges:
#       - cmd: collect-static-zun
#
# {% elif grains['os_family'] == 'RedHat' %}
#
# ## This is a consequence of zun requiring python3+, RDO still using python2, and django requiring python3 explicitly
# ## Remote this when ussuri comes out or python3 support gets added
# python -m pip install --upgrade pip setuptools && touch /root/pip_updated:
#   cmd.run:
#     - creates: /root/pip_updated
#
# zun_ui_requirements:
#   cmd.run:
#     - name: pip install -r /usr/share/openstack-dashboard/zun-ui/requirements.txt
#     - onchanges:
#       - git: zun_latest
#
# install_zun_ui:
#   cmd.run:
#     - name: python2 setup.py install
#     - cwd: /usr/share/openstack-dashboard/zun-ui/
#     - onchanges:
#       - cmd: zun_ui_requirements
#
# collect-static-zun:
#   cmd.run:
#     - name: python2 manage.py collectstatic --noinput
#     - cwd: /usr/share/openstack-dashboard/
#     - onchanges:
#       - cmd: install_zun_ui
#
# compress-static-zun:
#   cmd.run:
#     - name: python2 manage.py compress
#     - cwd: /usr/share/openstack-dashboard/
#     - onchanges:
#       - cmd: collect-static-zun
#
# {% endif %}
