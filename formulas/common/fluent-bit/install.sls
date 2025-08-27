# Ensure the namespace for EFK stack exists
efk_namespace:
  k8s.namespace_present:
    - namespace: {{ pillar.get('efk_namespace', 'efk') }}

# Manage Helm repository for Fluent
fluent_repo:
  helm.repo_managed:
    - present:
      - name: fluent
        url: https://fluent.github.io/helm-charts
    - repo_update: True

# Install Fluent Operator using Helm
fluent_operator_helm_install:
  helm.release_present:
    - name: fluent-operator
    - chart: fluent/fluent-operator
    - version: {{ pillar.get('fluent_operator_version', '2.10.0') }}
    - namespace: {{ pillar.get('efk_namespace', 'efk') }}
    - force: True
    - require:
      - k8s: efk_namespace
      - helm: fluent_repo

# Render Fluent Bit configuration manifest for Fluent Operator
render_fluent_bit_config:
  file.managed:
    - name: /tmp/fluent-bit-config.yaml
    - source: salt://formulas/common/fluent-bit/files/fluent-bit-config.j2
    - template: jinja
    - makedirs: True
    - require:
      - helm: fluent_operator_helm_install

# Apply Fluent Bit configuration using Fluent Operator CRDs
apply_fluent_bit_config:
  cmd.run:
    - name: kubectl apply -f /tmp/fluent-bit-config.yaml
    - require:
      - file: render_fluent_bit_config
    - onchanges:
      - file: render_fluent_bit_config