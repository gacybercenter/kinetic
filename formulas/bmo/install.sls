include:
  - /formulas/common/k8s-certmanager/install

# Validate deployment options
validate_deployment_bmo_ironic:
  test.fail_without_changes:
    - name: "Nothing to deploy: deploy_bmo and deploy_ironic are both false"
    - failhard: True
    - unless: {{ pillar['deploy_bmo'] }} || {{ pillar['deploy_ironic'] }}
valid_deployment_mariadb_tls:
  test.fail_without_changes:
    - name: "MariaDB deployment requires TLS"
    - failhard: True
    - onlyif: {{ pillar['deploy_mariadb'] }} && ! {{ pillar['deploy_tls'] }}

# Install dependencies (kustomize, kubectl)
install_dependencies:
  pkg.installed:
    - pkgs:
        - kubectl
        - curl
        - apache2-utils
        - golang
  cmd.run:
    - name: |
        curl -sL https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.4.1/kustomize_v5.4.1_linux_amd64.tar.gz | tar xz -C /usr/local/bin/ && chmod +x /usr/local/bin/kustomize
    - unless: test -x /usr/local/bin/kustomize && kustomize version | grep v5.4.1
    - require:
      - pkg: install_dependencies

clone_bmo_repo:
  git.cloned:
    - name: https://github.com/metal3-io/baremetal-operator.git
    - branch: {{ pillar['bmo_version'] }}
    - target: {{ pillar['script_dir'] }}
    - require:
      - pkg: install_dependencies
    - unless: -f {{ pillar['script_dir'] }}

bmo_ironic_env:
  file.managed:
    - name: {{ pillar['script_dir'] }}/config/default/ironic.env
    - source: salt://formulas/bmo/files/ironic.env.j2
    - template: jinja
    - mode: 644
    - require:
      - file: temp_overlay_dirs

ironic_bmo_configmap:
  file.managed:
    - name: {{ pillar['script_dir'] }}/ironic-deployment/default/ironic_bmo_configmap.env
    - source: salt://formulas/bmo/files/ironic.env.j2
    - mode: 644
    - template: jinja
    - require:
      - file: temp_overlay_dirs

