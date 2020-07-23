include:
  - /formulas/common/base
  - /formulas/common/networking
  - /formulas/common/install

pxe_packages:
  pkg.installed:
    - pkgs:
      - build-essential
      - python3-tornado
      - apache2
      - libapache2-mod-wsgi-py3
      - git
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
