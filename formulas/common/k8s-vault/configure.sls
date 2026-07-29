include:
  - /formulas/common/k8s-vault/install

{% set vault = pillar['res-k8s']['vault'] %}
{% set vault_namespace = vault['global']['namespace'] %}
{# Default transport: Kubernetes API server service proxy (Vault API is not
   exposed outside the cluster). Override with res-k8s:vault:addr for direct
   https:// access if the API is ever exposed. #}
{% set vault_addr = vault.get('addr', 'k8s://' ~ vault_namespace ~ '/vault:8200') %}
{% set vault_sa = vault.get('auth_sa', 'rook-vault-auth') %}

# ======================
# Kubernetes prerequisites for Vault Kubernetes auth
# ======================

rook_vault_sa:
  k8s.serviceaccount_present:
    - name: {{ vault_sa }}
    - namespace: {{ vault_namespace }}

vault_tokenreview_binding:
  k8s.clusterrolebinding_present:
    - name: vault-tokenreview-binding
    - cluster_role: system:auth-delegator
    - service_accounts:
      - {{ vault_namespace }}:{{ vault_sa }}
    - require:
      - k8s: rook_vault_sa

# Long-lived ServiceAccount token Secret (required on Kubernetes 1.24+)
rook_vault_sa_token:
  k8s.serviceaccount_token_secret_present:
    - name: {{ vault_sa }}-token
    - namespace: {{ vault_namespace }}
    - service_account: {{ vault_sa }}
    - require:
      - k8s: rook_vault_sa

# ======================
# Vault configuration (direct API, token from vault-init k8s Secret)
# ======================

vault_kubernetes_auth:
  vault.auth_method_present:
    - name: kubernetes
    - method: kubernetes
    - vault_addr: {{ vault_addr }}
    - namespace: {{ vault_namespace }}
    - require:
      - k8s: rook_vault_sa_token

vault_kubernetes_auth_config:
  vault.kubernetes_auth_configured:
    - name: kubernetes-auth-config
    - sa_secret_name: {{ vault_sa }}-token
    - sa_namespace: {{ vault_namespace }}
    - vault_addr: {{ vault_addr }}
    - namespace: {{ vault_namespace }}
    - require:
      - vault: vault_kubernetes_auth

vault_rook_secrets_engine:
  vault.secrets_engine_present:
    - name: rook
    - engine_type: kv
    - vault_addr: {{ vault_addr }}
    - namespace: {{ vault_namespace }}
    - require:
      - vault: vault_kubernetes_auth_config

vault_rook_policy:
  vault.policy_present:
    - name: rook
    - policy_pillar: res-k8s:vault:policies:rook
    - vault_addr: {{ vault_addr }}
    - namespace: {{ vault_namespace }}
    - require:
      - vault: vault_rook_secrets_engine

# Role for the Rook operator and OSDs
vault_rook_role:
  vault.kubernetes_role_present:
    - name: {{ vault_namespace }}
    - bound_service_account_names:
      - rook-ceph-system
      - rook-ceph-osd
    - bound_service_account_namespaces:
      - {{ vault_namespace }}
    - policies:
      - rook
    - ttl: 1440h
    - vault_addr: {{ vault_addr }}
    - namespace: {{ vault_namespace }}
    - require:
      - vault: vault_rook_policy

# Role for CSI pods (PVC encryption)
vault_csi_role:
  vault.kubernetes_role_present:
    - name: rook-ceph-csi
    - bound_service_account_names:
      - rook-ceph-rbd-csi-ceph-com-ctrlplugin-sa
      - rook-ceph-rbd-csi-ceph-com-nodeplugin-sa
    - bound_service_account_namespaces:
      - {{ vault_namespace }}
    - policies:
      - rook
    - ttl: 1440h
    - vault_addr: {{ vault_addr }}
    - namespace: {{ vault_namespace }}
    - require:
      - vault: vault_rook_policy

# ======================
# Break-glass admin AppRole
# ======================

vault_admin_policy:
  vault.policy_present:
    - name: admin
    - policy_pillar: res-k8s:vault:policies:admin
    - vault_addr: {{ vault_addr }}
    - namespace: {{ vault_namespace }}
    - require:
      - vault: vault_kubernetes_auth_config

vault_approle_auth:
  vault.auth_method_present:
    - name: approle
    - method: approle
    - vault_addr: {{ vault_addr }}
    - namespace: {{ vault_namespace }}
    - require:
      - vault: vault_admin_policy

vault_admin_approle:
  vault.approle_present:
    - name: admin
    - token_policies:
      - admin
    - token_ttl: 1h
    - token_max_ttl: 4h
    - vault_addr: {{ vault_addr }}
    - namespace: {{ vault_namespace }}
    - require:
      - vault: vault_approle_auth

# Store break-glass credentials in a k8s Secret (never printed)
vault_admin_approle_creds:
  vault.approle_secret_present:
    - name: vault-admin-approle
    - role_name: admin
    - k8s_namespace: {{ vault_namespace }}
    - vault_addr: {{ vault_addr }}
    - namespace: {{ vault_namespace }}
    - require:
      - vault: vault_admin_approle
