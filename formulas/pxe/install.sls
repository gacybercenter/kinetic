build-essential:
  pkg.installed

python3-tornado:
  pkg.installed

apache2:
  pkg.installed

libapache2-mod-wsgi-py3:
  pkg.installed

git:
  pkg.installed:
    - reload_modules: True

python3-pyinotify:
  pkg.installed:
    - reload_modules: True

redfish_pip:
  pip.installed:
    - name: redfish
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

pyghmi_pip:
  pip.installed:
    - name: pyghmi
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

salt-minion_inotify_watch:
  cmd.run:
    - name: 'salt-call service.restart salt-minion'
    - bg: True
    - onchanges:
      - pkg: python3-pyinotify
