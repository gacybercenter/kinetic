include:
  - /formulas/common/helm/install

# Ensure Helm is installed and configured before proceeding
helm_installed:
  test.nop:
    - require:
      - sls: /formulas/common/helm/install

# Install the helm-git plugin required for OpenStack Helm
install_helm_git_plugin:
  cmd.run:
    - name: helm plugin install https://opendev.org/openstack/openstack-helm-plugin
    - unless: helm plugin list | grep -q "osh"
    - require:
      - test: helm_installed

# Add the OpenStack Helm repository using the custom Helm module
add_openstack_helm_repo:
  k8s_helm.helm_repo_present:
    - repo_name: openstack-helm
    - repo_url: https://tarballs.opendev.org/openstack/openstack-helm
    - require:
      - test: helm_installed
      - cmd: install_helm_git_plugin