# Re-apply only the Nova formula. Use this for route, middleware, and
# chart updates without running the rest of the compute kit.
#
#   salt-run state.orchestrate orch.k8s-osh-nova pillar='{"k8s": "master-ss3-0"}'

{% set k8s = salt['pillar.get']('k8s') %}

deploy_osh_nova:
  salt.state:
    - tgt: {{ k8s }}
    - sls:
      - formulas.nova
