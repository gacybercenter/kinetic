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

salt-minion_watch:
  service.running:
    - name: salt-minion
    - watch:
      - python3-pyinotify
