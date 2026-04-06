{% set k8s = salt['pillar.get']('k8s') %}

# Step 2: Apply OLM configuration
k8s_olm_install:
  salt.state:
    - tgt: '{{ k8s }}'
    - sls: formulas.olm
