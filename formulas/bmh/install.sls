Install Salt Kubernetes extension:
  pip.installed:
    - bin_env: '/usr/bin/salt-pip'
    - name: saltext-kubernetes