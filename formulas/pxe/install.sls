tftpd-hpa:
  pkg.installed

apache2:
  pkg.installed

php7.0:
  pkg.installed

git:
  pkg.installed
    - reload_modules: True
