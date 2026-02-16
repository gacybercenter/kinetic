{% set k8s = salt['pillar.get']('k8s') %}

# Step 2: Apply EFK configuration (Elasticsearch via Helm)
k8s_efk_install:
  salt.state:
    - tgt: '{{ k8s }}'
    - sls: formulas.common.k8s-efk.install
