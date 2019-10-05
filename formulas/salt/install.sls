haveged:
  pkg.installed

curl:
  pkg.installed

python3-pip:
  pkg.installed:
   - reload_modules: true

pyghmi:
  pip.installed:
    - require:
      - pkg: python3-pip
