include:
  - /formulas/common/base
  - /formulas/common/networking
  - /formulas/common/install

salt_pkgs:
  pkg.installed:
    - pkgs:
      - python3-tornado
      - salt-api
      - sqlite3
      - haveged
      - curl
      - python3-pygit2
    - reload_modules: True

cryptography_pip:
  pip.installed:
    - name: cryptography
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True
