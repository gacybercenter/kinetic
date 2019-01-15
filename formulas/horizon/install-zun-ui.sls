python-pip:
  pkg.installed

zun_latest:
  git.latest:
    - name: https://github.com/openstack/zun-ui.git
    - branch: stable/rocky
    - target: /usr/share/openstack-dashboard/zun-ui/
    - force_clone: true

/usr/share/openstack-dashboard/openstack_dashboard/enabled/_0330_cloud_shell.py:
  file.managed:
    - source: https://raw.githubusercontent.com/openstack/zun-ui/stable/rocky/zun_ui/enabled/_0330_cloud_shell.py
    - source_hash: salt://formulas/horizon/files/url_hash

/usr/share/openstack-dashboard/openstack_dashboard/enabled/_1330_project_container_panalgroup.py:
  file.managed:
    - source: https://raw.githubusercontent.com/openstack/zun-ui/stable/rocky/zun_ui/enabled/_1330_project_container_panelgroup.py
    - source_hash: salt://formulas/horizon/files/url_hash

/usr/share/openstack-dashboard/openstack_dashboard/enabled/_1331_project_container_containers_panel.py:
  file.managed:
    - source: https://raw.githubusercontent.com/openstack/zun-ui/stable/rocky/zun_ui/enabled/_1331_project_container_containers_panel.py
    - source_hash: salt://formulas/horizon/files/url_hash

/usr/share/openstack-dashboard/openstack_dashboard/enabled/_1332_project_container_capsules_panel.py:
  file.managed:
    - source: https://raw.githubusercontent.com/openstack/zun-ui/stable/rocky/zun_ui/enabled/_1332_project_container_capsules_panel.py
    - source_hash: salt://formulas/horizon/files/url_hash

/usr/share/openstack-dashboard/openstack_dashboard/enabled/_2330_admin_container_panelgroup.py:
  file.managed:
    - source: https://raw.githubusercontent.com/openstack/zun-ui/stable/rocky/zun_ui/enabled/_2330_admin_container_panelgroup.py
    - source_hash: salt://formulas/horizon/files/url_hash

/usr/share/openstack-dashboard/openstack_dashboard/enabled/_2331_admin_container_images_panel.py:
  file.managed:
    - source: https://raw.githubusercontent.com/openstack/zun-ui/stable/rocky/zun_ui/enabled/_2331_admin_container_images_panel.py
    - source_hash: salt://formulas/horizon/files/url_hash

/usr/share/openstack-dashboard/openstack_dashboard/local/local_settings.d/_0330_cloud_shell_settings.py:
  file.managed:
    - source: salt://formulas/horizon/files/_0330_cloud_shell_settings.py

pip install -e /usr/share/openstack-dashboard/zun-ui/:
  cmd.run

collect-static:
  cmd.run:
    - name: python manage.py collectstatic --noinput
    - cwd : /usr/share/openstack-dashboard/

compress-static:
  cmd.run:
    - name: python manage.py compress
    - cwd : /usr/share/openstack-dashboard/
