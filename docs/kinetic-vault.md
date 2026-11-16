# kinetic-vault Module

SaltStack execution and state modules for managing HashiCorp Vault via its
direct HTTP API (through the Kubernetes API server proxy). This module is
designed to work in environments where the Salt minion cannot reach Vault
directly over the network.

## Features

- Initialize Vault and store the root token + recovery keys (or KMS
  recovery material) in a Kubernetes Secret
- Enable and configure auth methods (especially the `kubernetes` auth
  method)
- Mount secrets engines (KV v2 by default)
- Create and manage ACL policies
- Manage Kubernetes auth roles and AppRoles
- Automatically write AppRole `role_id` / `secret_id` pairs into
  Kubernetes Secrets for use by other workloads

## How it works

- All Vault API calls go through the Kubernetes API server proxy
  (`k8s://<namespace>/<service>:<port>`) so no direct network connectivity
  from the Salt minion to Vault is required.
- Sensitive bootstrap material (root token, unseal/recovery keys) is
  stored in a Kubernetes Secret (`vault-init` by default) rather than on
  the Salt minion filesystem.
- The module supports both manual unseal and KMS auto-unseal
  (`kms_unseal: true`) configurations.

## Usage Examples

### Initialize Vault

```yaml
vault_initialized:
  vault.initialized:
    - name: vault-init
    - vault_addr: k8s://rook-ceph/vault:8200
    - namespace: rook-ceph
    - secret_name: vault-init
    - kms_unseal: true
    - key_shares: 5
    - key_threshold: 3
```

When `kms_unseal` is `true`, the module uses `recovery_shares` /
`recovery_threshold` instead of the classic `secret_shares` /
`secret_threshold` parameters.

### Enable and configure Kubernetes auth

```yaml
vault_kubernetes_auth:
  vault.auth_method_present:
    - name: kubernetes
    - method: kubernetes
    - vault_addr: k8s://rook-ceph/vault:8200
    - namespace: rook-ceph
    - secret_name: vault-init

vault_kubernetes_auth_config:
  vault.kubernetes_auth_configured:
    - name: kubernetes-auth-config
    - sa_secret_name: vault-auth-token
    - sa_namespace: rook-ceph
    - kubernetes_host: https://kubernetes.default.svc.cluster.local
    - issuer: https://kubernetes.default.svc.cluster.local
    - mount: kubernetes
    - vault_addr: k8s://rook-ceph/vault:8200
    - namespace: rook-ceph
    - secret_name: vault-init
    - require:
      - vault: vault_kubernetes_auth
```

### Mount a KV v2 secrets engine

```yaml
vault_rook_engine:
  vault.secrets_engine_present:
    - name: rook
    - engine_type: kv
    - vault_addr: k8s://rook-ceph/vault:8200
    - namespace: rook-ceph
    - secret_name: vault-init
```

### Create a policy

```yaml
vault_rook_policy:
  vault.policy_present:
    - name: rook
    - policy_pillar: 'vault:policies:rook'
    - vault_addr: k8s://rook-ceph/vault:8200
    - namespace: rook-ceph
    - secret_name: vault-init
```

### Create a Kubernetes auth role

```yaml
vault_rook_role:
  vault.kubernetes_role_present:
    - name: rook-ceph-osd
    - role_name: rook-ceph-osd
    - bound_service_account_names:
        - rook-ceph-osd
    - bound_service_account_namespaces:
        - rook-ceph
    - policies:
        - rook
    - ttl: 1440h
    - audience: https://kubernetes.default.svc.cluster.local
    - mount: kubernetes
    - vault_addr: k8s://rook-ceph/vault:8200
    - namespace: rook-ceph
    - secret_name: vault-init
```

### Create an AppRole and store its credentials in a Secret

```yaml
vault_rook_approle:
  vault.approle_present:
    - name: rook
    - role_name: rook
    - token_policies:
        - rook
    - token_ttl: 1h
    - token_max_ttl: 4h
    - mount: approle
    - vault_addr: k8s://rook-ceph/vault:8200
    - namespace: rook-ceph
    - secret_name: vault-init

vault_rook_approle_secret:
  vault.approle_secret_present:
    - name: rook-vault-approle
    - role_name: rook
    - k8s_secret_name: rook-vault-approle
    - k8s_namespace: rook-ceph
    - regenerate: false
    - mount: approle
    - vault_addr: k8s://rook-ceph/vault:8200
    - namespace: rook-ceph
    - secret_name: vault-init
    - require:
      - vault: vault_rook_approle
```

## Important Notes

- Most states require either a `token` or a `secret_name` pointing at the
  `vault-init` Secret created by the `initialized` state.
- The `kubernetes_auth_configured` state expects a ServiceAccount token
  Secret containing the keys `token` and `ca.crt` (the format produced by
  the `kubernetes` secret type with `kubernetes.io/service-account.name`).
- AppRole credentials are stored as `role_id` and `secret_id` in the
  target Kubernetes Secret. Workloads that need these values should mount
  that Secret.
- The module currently has no automatic "unseal" state — it assumes either
  KMS auto-unseal or that a human (or separate orchestration) will unseal
  Vault after initialization.

Last updated: September 2026
```