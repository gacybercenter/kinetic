zun_latest:
  git.latest:
    - name: https://opendev.org/openstack/zun-ui.git
    - branch: stable/train
    - target: /usr/share/openstack-dashboard/zun-ui/
    - force_clone: true

0330_cloud_shell.py:
  file.copy:
    - name: /usr/share/openstack-dashboard/openstack_dashboard/enabled/_0330_cloud_shell.py
    - source: /usr/share/openstack-dashboard/zun-ui/zun_ui/enabled/_0330_cloud_shell.py

1330_project_container_panelgroup.py:
  file.copy:
    - name: /usr/share/openstack-dashboard/openstack_dashboard/enabled/_1330_project_container_panelgroup.py
    - source: /usr/share/openstack-dashboard/zun-ui/zun_ui/enabled/_1330_project_container_panelgroup.py

1331_project_container_containers_panel.py:
  file.copy:
    - name: /usr/share/openstack-dashboard/openstack_dashboard/enabled/_1331_project_container_containers_panel.py
    - source: /usr/share/openstack-dashboard/zun-ui/zun_ui/enabled/_1331_project_container_containers_panel.py

1332_project_container_capsules_panel.py:
  file.copy:
    - name: /usr/share/openstack-dashboard/openstack_dashboard/enabled/_1332_project_container_capsules_panel.py
    - source: /usr/share/openstack-dashboard/zun-ui/zun_ui/enabled/_1332_project_container_capsules_panel.py

2330_admin_container_panelgroup.py:
  file.copy:
    - name: /usr/share/openstack-dashboard/openstack_dashboard/enabled/_2330_admin_container_panelgroup.py
    - source: /usr/share/openstack-dashboard/zun-ui/zun_ui/enabled/_2330_admin_container_panelgroup.py

2331_admin_container_images_panel.py:
  file.copy:
    - name: /usr/share/openstack-dashboard/openstack_dashboard/enabled/_2331_admin_container_images_panel.py
    - source: /usr/share/openstack-dashboard/zun-ui/zun_ui/enabled/_2331_admin_container_images_panel.py

2332_admin_container_hosts_panel.py:
  file.copy:
    - name: /usr/share/openstack-dashboard/openstack_dashboard/enabled/_2332_admin_container_hosts_panel.py
    - source: /usr/share/openstack-dashboard/zun-ui/zun_ui/enabled/_2332_admin_container_hosts_panel.py

2333_admin_container_containers_panel.py:
  file.copy:
    - name: /usr/share/openstack-dashboard/openstack_dashboard/enabled/_2333_admin_container_containers_panel.py
    - source: /usr/share/openstack-dashboard/zun-ui/zun_ui/enabled/_2333_admin_container_containers_panel.py

/usr/share/openstack-dashboard/openstack_dashboard/local/local_settings.d/_0330_cloud_shell_settings.py:
  file.managed:
    - source: salt://formulas/horizon/files/_0330_cloud_shell_settings.py

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
