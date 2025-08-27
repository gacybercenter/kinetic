efk_namespace:
  k8s.namespace_present:
    - namespace: {{ pillar.get('efk_namespace', 'efk') }}

opensearch_repo:
  helm.repo_managed:
    - present:
      - name: opensearch
        url: https://opensearch-project.github.io/helm-charts/
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
    - require:
      - k8s: efk_namespace
      - helm: opensearch_repo