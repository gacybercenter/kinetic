zun_latest:
  git.latest:
    - name: https://opendev.org/openstack/zun-ui.git
    - branch: stable/train
    - target: /usr/share/openstack-dashboard/zun-ui/
    - force_clone: true

copy_zun_panels:
  module.run:
    - file.copy:
      - src: /usr/share/openstack-dashboard/zun-ui/zun_ui/enabled/
      - dst: /usr/share/openstack-dashboard/openstack_dashboard/enabled/
      - recurse: True

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
