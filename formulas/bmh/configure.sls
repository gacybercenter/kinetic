include:
- /formulas/bmh/install

# Ensure Helm is installed
helm_installed:
  cmd.run:
    - name: helm version --short
    - unless: test -f /usr/local/bin/helm