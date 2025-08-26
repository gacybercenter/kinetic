efk_namespace:
  k8s.namespace_present:
    - name: {{ pillar.get('efk_namespace', 'efk') }}
    - require:
      - sls: common.k8s

elastic_repo:
  helm.repo_managed:
    - name: elastic
    - url: https://helm.elastic.co

elasticsearch_helm_install:
  helm.release_present:
    - name: elasticsearch
    - chart: elastic/elasticsearch
    - version: {{ pillar.get('elasticsearch_version') }}
    - namespace: {{ pillar.get('efk_namespace') }}
    - values: {{ salt['jinja.load_template']('/formulas/common/k8s-efk/files/elasticsearch-values.j2', context={'pillar': pillar}) | yaml }}
    - require:
      - k8s: efk_namespace
      - helm: elastic_repo