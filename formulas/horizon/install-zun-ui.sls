zun_latest:
  git.latest:
    - name: https://opendev.org/openstack/zun-ui.git
    - branch: stable/train
    - target: /usr/share/openstack-dashboard/zun-ui/
    - force_clone: true

copy_panels:
  file.copy_:
    - name: /usr/share/openstack-dashboard/openstack_dashboard/local/enabled/
    - source: /usr/share/openstack-dashboard/zun-ui/zun_ui/enabled/*
    - makedirs: True

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
