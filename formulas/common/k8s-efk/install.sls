efk_namespace:
  k8s.namespace_present:
    - namespace: {{ pillar.get('efk_namespace', 'efk') }}


render_opensearch_security_config:
  file.managed:
    - name: /tmp/opensearch-security-config.yaml
    - source: salt://formulas/common/k8s-efk/files/opensearch-security-config.j2
    - template: jinja
    - makedirs: True


apply_opensearch_security_config:
  cmd.run:
    - name: kubectl apply -f /tmp/opensearch-security-config.yaml
    - require:
      - file: render_opensearch_security_config
    - onchanges:
      - file: render_opensearch_security_config

render_opensearch_tls_cert:
  file.managed:
    - name: /tmp/opensearch-tls-cert.yaml
    - source: salt://formulas/common/k8s-efk/files/opensearch-tls-cert.j2
    - template: jinja
    - makedirs: True

apply_opensearch_tls_cert:
  cmd.run:
    - name: kubectl apply -f /tmp/opensearch-tls-cert.yaml
    - require:
      - file: render_opensearch_tls_cert
    - onchanges:
      - file: render_opensearch_tls_cert

opensearch_repo:
  helm.repo_managed:
    - name: opensearch
    - url: https://opensearch-project.github.io/helm-charts/
    - repo_update: True


render_opensearch_values:
  file.managed:
    - name: /tmp/opensearch-values.yaml
    - source: salt://formulas/common/k8s-efk/files/opensearch-values.j2
    - template: jinja


opensearch_helm_install:
  helm.release_present:
    - name: opensearch
    - chart: opensearch/opensearch
    - version: {{ pillar.get('opensearch_version', '2.12.0') }}
    - namespace: {{ pillar.get('efk_namespace', 'efk') }}
    - values: /tmp/opensearch-values.yaml
    - force: True
    - require:
      - k8s: efk_namespace
      - helm: opensearch_repo
      - cmd: apply_opensearch_security_config
      - cmd: apply_opensearch_tls_cert
      - file: render_opensearch_values