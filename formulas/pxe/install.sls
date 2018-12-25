build-essential:
  pkg.installed

tftpd-hpa:
  pkg.installed

apache2:
  pkg.installed

php7.2:
  pkg.installed

git:
  pkg.installed:
    - reload_modules: True

uuid-runtime:
  pkg.installed

python-pyinotify:
  pkg.installed:
    - reload_modules: True

salt-minion_watch:
  service.running:
    - name: salt-minion
    - watch:
      - python-pyinotify
