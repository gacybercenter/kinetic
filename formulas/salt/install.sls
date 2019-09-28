haveged:
  pkg.installed

curl:
  pkg.installed

python-pip:
  pkg.installed:
   - reload_modules: true

pyghmi:
  pip.installed:
    - require:
      - pkg: python-pip
