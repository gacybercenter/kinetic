include:
  - /formulas/ironic-operator/install


git_ironic_repo:
  git.config_set:
    - name: safe.directory
    - value: {{ pillar['ironic_op_dir'] }}
    - global: True

clone_ironic_repo:
  git.cloned:
    - name: https://github.com/metal3-io/ironic-standalone-operator
    - branch: {{ pillar['ironic_op_release'] }}
    - target: {{ pillar['ironic_op_dir'] }}
    - require:
      - sls: /formulas/ironic-operator/install
      - git: git_ironic_repo

ironic-op-ns:
  file.managed:
    - name: {{ pillar['ironic_op_dir']}}/config/default/kustomization.yaml
    - template: jinja
    - source: salt://formulas/ironic-operator/files/ironic_kustom.yaml.j2
    - require:
      - git: clone_ironic_repo

check_ironic_operator:
  k8s.ironic_operator_present:
    - namespace: {{ pillar['irso_namespace'] }}
    - deployment_name: {{ pillar['irso_namespace'] }}-controller-manager
    - timeout: 60