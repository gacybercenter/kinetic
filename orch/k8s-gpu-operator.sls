# Deploy the NVIDIA GPU Operator.
#
#   salt-run state.orchestrate orch.k8s-gpu-operator pillar='{"k8s": "<minion>"}'

{% set k8s = salt['pillar.get']('k8s') %}

deploy_gpu_operator:
  salt.state:
    - tgt: {{ k8s }}
    - sls:
      - formulas.common.k8s-gpu-operator
