include:
  - /formulas/common/k8s-mariadb

ironic_dependancies:
  pkg.installed:
    - pkgs: 
      - podman

tls_generate_pip:
  pip.installed:
    - name: cryptography
    - pip_bin: /usr/bin/salt-pip