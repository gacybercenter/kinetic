# Ensure the namespace for EFK stack exists
efk_namespace:
  k8s.namespace_present:
    - namespace: {{ pillar.get('efk_namespace', 'efk') }}
    - require:
      - sls: common.k8s

# Manage Helm repository for Fluent
fluent_repo:
  helm.repo_managed:
    - present:
      - name: fluent
        url: https://fluent.github.io/helm-charts
    - repo_update: Truefs
    - require:
      - sls: common.helm

# Render Fluent Bit values file
render_fluent_bit_values:
  file.managed:
    - name: /tmp/fluent-bit-values.yaml
    - source: salt://formulas/common/fluent-bit/files/fluent-bit-values.j2
    - template: jinja
    - makedirs: True
    - require:
      - sls: common.helm

# Install or upgrade Fluent Bit using direct Helm command
fluent_bit_helm_install:
  cmd.run:
    - name: |
        helm upgrade --install fluent-bit fluent/fluent-bit \
          --version {{ pillar.get('fluent_bit_version', '0.47.0') }} \
          --namespace {{ pillar.get('efk_namespace', 'efk') }} \
          --values /tmp/fluent-bit-values.yaml \
          --force
    - unless: helm list -n {{ pillar.get('efk_namespace', 'efk') }} | grep fluent-bit
    - require:
      - k8s: efk_namespace
      - helm: fluent_repo
      - file: render_fluent_bit_values