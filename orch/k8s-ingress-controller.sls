# One external Gateway (Traefik + MetalLB). Not the dual internal/external stack.
# pepper --client='runner' state.orchestrate orch.k8s-ingress-controller pillar='{"k8s": "master-ss3-0"}'

{% set k8s = salt['pillar.get']('k8s') %}

deploy_external_gateway:
  salt.state:
    - tgt: {{ k8s }}
    - sls:
      - formulas.common.k8s-ingress-controller
    - pillar:
        ingress_gateways: external