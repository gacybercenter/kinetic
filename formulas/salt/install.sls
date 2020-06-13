
salt_pkgs:
  pkg.installed:
    - pkgs:
      - python3-tornado
      - salt-api
      - sqlite3
      - haveged
      - curl
