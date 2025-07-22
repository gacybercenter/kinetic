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



ensure_tls_secret:
  k8s.tls_secret_present:
    - namespace: {{ pillar['bmo_namespace'] }}
    - secret_name: ironic-tls
    - common_name: ironic-operator
    - validity_days: 365

