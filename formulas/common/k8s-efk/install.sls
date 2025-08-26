efk_namespace:
  k8s.namespace_present:
    - name: {{ pillar.get('efk_namespace', 'efk') }}

elastic_repo:
  helm.repo_managed:
    - present:
      - name: elastic
        url: https://helm.elastic.co

render_elasticsearch_values:
  file.managed:
    - name: /tmp/elasticsearch-values.yaml
    - source: salt://formulas/common/k8s-efk/files/elasticsearch-values.j2
    - template: jinja

elasticsearch_helm_install:
  helm.release_present:
    - name: elasticsearch
    - chart: elastic/elasticsearch
    - version: {{ pillar.get('elasticsearch_version') }}
    - namespace: {{ pillar.get('efk_namespace') }}
    - values: /tmp/elasticsearch-values.yaml
    - require:
      - k8s: efk_namespace
      - helm: elastic_repo