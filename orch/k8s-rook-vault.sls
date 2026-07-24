{% set k8s = salt['pillar.get']('k8s') %}

# Step 2: Apply vault configs
k8s_vault_install:
  salt.state:
    - tgt: '{{ k8s }}'
    - sls: formulas.common.k8s-vault
