zun_latest:
  git.latest:
    - name: https://github.com/openstack/zun-ui.git
    - branch: stable/rocky
    - target: /usr/share/openstack-dashboard/zun-ui/
    - force_clone: true

/usr/share/openstack-dashboard/zun-ui/requirements.txt:
  file.managed:
    - source: salt://formulas/devvm/files/requiremnts.txt

0330_cloud_shell.py:
  file.copy:
    - name: /usr/share/openstack-dashboard/openstack_dashboard/enabled/_0330_cloud_shell.py
    - source: /usr/share/openstack-dashboard/zun-ui/zun-ui/enabled/_0330_cloud_shell.py

1330_project_container_panalgroup.py:
  file.copy:
    - name: /usr/share/openstack-dashboard/openstack_dashboard/enabled/_1330_project_container_panalgroup.py
    - source: /usr/share/openstack-dashboard/zun-ui/zun-ui/enabled/_1330_project_container_panalgroup.py

1331_project_container_containers_panel.py:
  file.copy:
    - name: /usr/share/openstack-dashboard/openstack_dashboard/enabled/_1331_project_container_containers_panel.py
    - source: /usr/share/openstack-dashboard/zun-ui/zun-ui/enabled/_1331_project_container_containers_panel.py

1332_project_container_capsules_panel.py:
  file.copy:
    - name: /usr/share/openstack-dashboard/openstack_dashboard/enabled/_1332_project_container_capsules_panel.py
    - source: /usr/share/openstack-dashboard/zun-ui/zun-ui/enabled/_1332_project_container_capsules_panel.py

2330_admin_container_panelgroup.py:
  file.copy:
    - name: /usr/share/openstack-dashboard/openstack_dashboard/enabled/_2330_admin_container_panelgroup.py
    - source: /usr/share/openstack-dashboard/zun-ui/zun-ui/enabled/_2330_admin_container_panelgroup.py

2331_admin_container_images_panel.py:
  file.copy:
    - name: /usr/share/openstack-dashboard/openstack_dashboard/enabled/_2331_admin_container_images_panel.py
    - source: /usr/share/openstack-dashboard/zun-ui/zun-ui/enabled/_2331_admin_container_images_panel.py

/usr/share/openstack-dashboard/openstack_dashboard/local/local_settings.d/_0330_cloud_shell_settings.py:
  file.managed:
    - source: salt://formulas/devvm/files/_0330_cloud_shell_settings.py

pip install -r /usr/share/openstack-dashboard/zun-ui/requiremts.txt:
  cmd.run

installzun-ui:
  cmd.run:
    - name: python setup.py install
    - cwd: /usr/share/openstack-dashboard/zun-ui/

collect-static:
  cmd.run:
    - name: python manage.py collectstatic --noinput
    - cwd: /usr/share/openstack-dashboard/

compress-static:
  cmd.run:
    - name: python manage.py compress
    - cwd: /usr/share/openstack-dashboard/

/usr/local/lib/python2.7/dist-packages/zunclient/common/websocketclient/websocketclient.py:
  file.managed:
    - source: salt://formulas/devvm/files/websocketclient.py

/usr/local/lib/python2.7/dist-packages/zun_ui/api/client.py:
  file.managed:
    - source: salt://formulas/devvm/files/client.py
