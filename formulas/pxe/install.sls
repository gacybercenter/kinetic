build-essential:
  pkg.installed

python3-tornado:
  pkg.installed

apache2:
  pkg.installed

php7.3:
  pkg.installed

git:
  pkg.installed:
    - reload_modules: True

uuid-runtime:
  pkg.installed

python3-pyinotify:
  pkg.installed:
    - reload_modules: True

salt-minion_inotify_watch:
  cmd.run:
    - name: 'salt-call service.restart salt-minion'
    - bg: True
    - onchanges:
      - pkg: python3-pyinotify
