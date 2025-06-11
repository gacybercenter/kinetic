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

ingress_values:
  file.managed:
    - name: /tmp/ingress-values.yaml
    - source: salt://formulas/bmo/files/ingress-values.j2
    - template: jinja

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
helm_ingress_repo:
  helm.repo_managed:
    - present:
      - name: nginx-ingress
        url: https://kubernetes.github.io/ingress-nginx
helm_ingress_release:
  helm.release_present:
    - name: nginx-ingress
    - chart: ingress-nginx/ingress-nginx
    - kvflags:
        values: /tmp/ingress-values.yaml
    - require:
      - file: ingress_values
    - watch:
      - file: ingress_values
        

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

ironic_bmo_configmap:
  file.managed:
    - name: {{ pillar['script_dir'] }}/ironic-deployment/default/ironic_bmo_configmap.env
    - source: salt://formulas/bmo/files/ironic.env.j2
    - mode: 644
    - template: jinja
bmo_deploy_env:
  file.managed:
    - name: {{ pillar['script_dir'] }}/deploy_env.sh
    - mode: 644
    - contents: |
        export IRONIC_HOST=bmo
        export IRONIC_HOST_IP=10.150.1.41