# k8s-vault

Deploys HashiCorp Vault in HA mode (Raft integrated storage, Azure Key Vault
auto-unseal) on Kubernetes and configures it as the KMS backend for Rook/Ceph
encryption (OSDs and CSI PVC encryption).

## Components

- **`install.sls`** - Adds the HashiCorp Helm repo, creates the Vault
  namespace, issues a cert-manager transport certificate (SANs for each Raft
  pod, the `vault` service, and the `vault-internal` headless service), and
  installs the `hashicorp/vault` chart via `k8s_helm.helm_release_present`.
  Chart values are pillar-driven (`res-k8s:vault`).
- **`configure.sls`** - Configures Vault for Rook using the idempotent
  `vault.*` states (backed by the `kinetic_vault` execution module, which
  talks to the Vault HTTP API directly - no kubectl exec):
  - ServiceAccount `rook-vault-auth` + `system:auth-delegator`
    ClusterRoleBinding + long-lived SA token Secret (required on k8s 1.24+)
  - `kubernetes` auth method enabled and configured from the SA token Secret
  - kv-v2 secrets engine mounted at `rook/`
  - `rook` policy (from pillar) and kubernetes auth roles `rook-ceph`
    (operator/OSD SAs) and `rook-ceph-csi` (CSI provisioner/nodeplugin SAs)
  - Break-glass `admin` policy + AppRole, with credentials stored in the
    `vault-admin-approle` k8s Secret (never printed)
- **`init.sls`** - Includes `configure.sls` (which includes `install.sls`).

## Orchestration flow (`orch/k8s-rook-vault.sls`)

1. Install the Vault Helm release (`install.sls`)
2. Wait for Vault pods to be Running
3. `kinetic_vault.initialize` - initializes Vault; the full init response
   (root token + recovery keys) is stored in the `vault-init` k8s Secret in
   `rook-ceph`. No manual unseal: Azure Key Vault auto-unseals the cluster.
4. Apply `configure.sls` (k8s auth, `rook` kv-v2 engine, policies, roles,
   break-glass AppRole)
5. `kinetic_vault.status` - verifies Vault is initialized and unsealed

## Token handling

The root token lives only in the `vault-init` k8s Secret. States and modules
fetch it at runtime via `kinetic_vault.get_root_token()` - no plaintext token
is stored in pillar or rendered into state files.

## Required pillar (summarized)

```yaml
res-k8s:
  vault:
    version: <chart version>
    nodes:            # Raft pod names, used for the transport cert SANs
      - vault-0
      - vault-1
      - vault-2
    global:
      namespace: rook-ceph
    # addr: https://vault.rook-ceph.svc:8200   (optional override)
    # auth_sa: rook-vault-auth                 (optional override)
    # ... helm chart values (HA raft config, Azure Key Vault seal, TLS) ...
    policies:
      rook: |
        path "rook/data/*" {
          capabilities = ["create", "read", "update", "delete", "list"]
        }
        path "rook/metadata/*" {
          capabilities = ["list", "read", "delete", "update"]
        }
        path "rook/data/ceph-csi/*" {
          capabilities = ["create", "read", "update", "delete", "list"]
        }
        path "rook/metadata/ceph-csi/*" {
          capabilities = ["list", "read", "delete", "update"]
        }
        path "sys/mounts" {
          capabilities = ["read"]
        }
        path "sys/internal/ui/mounts/*" {
          capabilities = ["read"]
        }
      admin: |
        path "*" {
          capabilities = ["create", "read", "update", "delete", "list", "sudo"]
        }
```

The Helm values under `res-k8s:vault` also carry the Vault server HA/Raft
configuration and the `azurekeyvault` seal stanza; see the chart values file
kept by `helm_release_present` (`keep_values_file: True`) for the rendered
result.

## Deprecated

`scripts/vault.sh` (imperative kubectl-exec configuration) is deprecated and
has been replaced by the `vault.*` states in `configure.sls`. It is kept for
reference only.

---

Last updated: July 2025
