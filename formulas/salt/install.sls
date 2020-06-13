
salt_pkgs:
  pkg.installed:
    - pkgs:
      - python3-tornado
      - salt-api
      - sqlite3
      - haveged
      - curl
    - reload_modules: True

cryptography_pip:
  pip.installed:
    - name: cryptography
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True
