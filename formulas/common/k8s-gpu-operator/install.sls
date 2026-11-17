include:
  - /formulas/common/helm

{# res-k8s:gpu:operator:chart and version pin the OCI release.
   res-k8s:gpu:operator:values is the chart values, including the MIG config.
   Helm --wait is off. The operator stays unready until a GPU node is labeled
   and the driver finishes, which is not a formula failure. #}
{% set gpu = pillar['res-k8s']['gpu']['operator'] %}
{% set ns = gpu.get('namespace', 'gpu-operator') %}

ensure_gpu_operator_namespace:
  k8s.namespace_present:
    - namespace: {{ ns }}

install_gpu_operator:
  k8s_helm.helm_release_present:
    - release_name: {{ gpu.get('release_name', 'gpu-operator') }}
    - chart_name: {{ gpu['chart'] | yaml_dquote }}
    - version: {{ gpu['version'] | yaml_dquote }}
    - namespace: {{ ns }}
    - pillar_key: res-k8s:gpu:operator:values
    - wait: false
    - wait_timeout: 600
    - wait_interval: 15
    - keep_values_file: true
    - require:
      - k8s: ensure_gpu_operator_namespace
