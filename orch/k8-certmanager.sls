{% set k8s = salt['pillar.get']('k8s') %}


# Step 2: Apply Cert-Manager configuration via Helm
k8s_certmanager_install:
  salt.state:
    - tgt: '{{ k8s }}'
    - sls: formulas.common.k8s-certmanager.configure