include:
  - /formulas/common/k8s-cnpg
  - /formulas/common/helm

{# Chart values live at osh:guacamole:values. Everything else (namespace,
   CNPG cluster, Gateway route) lives beside that key, not inside it. #}
{% set guac = pillar['osh']['guacamole'] %}
{% set ns = guac.get('namespace', 'guacamole') %}

ensure_helmforge_repo:
  k8s_helm.helm_repo_present:
    - repo_name: helmforge
    - repo_url: https://repo.helmforge.dev

ensure_guacamole_namespace:
  k8s.namespace_present:
    - namespace: {{ ns }}
