# Deploy the NVIDIA GPU Operator.
#
#   salt-run state.orchestrate orch.k8s-runai pillar='{"k8s": "<minion>"}'

{% set k8s = salt['pillar.get']('k8s') %}

deploy_gpu_runai:
  salt.state:
    - tgt: {{ k8s }}
    - sls:
      - formulas.runai
