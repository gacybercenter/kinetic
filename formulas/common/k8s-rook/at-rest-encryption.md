---

# NIST Evidence Report
**Control Family:** System and Communications Protection (SC) / Media Protection (MP)
**Feature:** Ceph-CSI RBD Persistent Volume Encryption using HashiCorp Vault KMS
**Environment:** Georgia Cyber Range / NCU Training Enclave (`rook-ceph` namespace)
**Date:** 29 July 2026
**Prepared by:** Infrastructure / Compliance Team

---

## 1. Control Mapping

| NIST SP 800-171 Rev 2 / 3 | Related 800-53 | Description |
|---------------------------|----------------|-------------|
| **3.13.11** | SC-28 | Cryptographic protection of CUI at rest |
| **3.13.16** | SC-12, SC-13 | Cryptographic key establishment and management |
| **3.13.8** | SC-8 | Transmission confidentiality (supporting) |
| **3.1.1 / 3.1.2** | AC-3, AC-6 | Least privilege / access enforcement (ServiceAccount binding) |
| **3.3.1 / 3.3.2** | AU-2, AU-3 | Audit events related to key access |

This implementation directly supports **CUI / FCI protection at rest** for block storage provisioned via the encrypted StorageClass.

---

## 2. Implementation Summary

Persistent volumes created with the StorageClass `rook-ceph-block-encrypted` are encrypted at the block level using **LUKS** (dm-crypt).

Encryption passphrases are:
- Generated uniquely per volume by Ceph-CSI
- Stored in **HashiCorp Vault** (KV v2 secrets engine at path `rook/ceph-csi/`)
- Retrieved only by authorized CSI ServiceAccounts via the **Vault Kubernetes Auth Method**
- Never stored in Kubernetes Secrets or etcd in plaintext

**Key Management Characteristics:**
- Keys are unique per volume
- Keys are stored outside the Ceph cluster
- Access is mediated by Kubernetes ServiceAccount identity + Vault policy
- Auto-unseal of Vault is performed via Azure Key Vault (separate control)

---

## 3. Technical Configuration Evidence

### 3.1 Vault Kubernetes Auth Method
- Auth method enabled at `auth/kubernetes`
- Token reviewer ServiceAccount: `rook-vault-auth`
- ClusterRoleBinding grants `system:auth-delegator`
- Roles created:
  - `rook-ceph` → bound to `rook-ceph-system`, `rook-ceph-osd`
  - `rook-ceph-csi` → bound to CSI ServiceAccounts

**CSI ServiceAccounts authorized:**
- `rook-ceph-rbd-csi-ceph-com-ctrlplugin-sa`
- `rook-ceph-rbd-csi-ceph-com-nodeplugin-sa`

### 3.2 Vault Policy (`rook`)
```hcl
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
```

### 3.3 Ceph-CSI KMS ConfigMap
`rook-ceph-csi-kms-config` contains:
```json
{
  "vault-kms": {
    "encryptionKMSType": "vault",
    "vaultAddress": "https://vault.rook-ceph.svc:8200",
    "vaultAuthPath": "/v1/auth/kubernetes/login",
    "vaultRole": "rook-ceph-csi",
    "vaultBackend": "kv-v2",
    "vaultBackendPath": "rook",
    "vaultPassphrasePath": "ceph-csi/",
    "vaultDestroyKeys": "true",
    "vaultCAVerify": "false"
  }
}
```

### 3.4 StorageClass
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: rook-ceph-block-encrypted
parameters:
  encrypted: "true"
  encryptionKMSID: "vault-kms"
  # ... standard RBD parameters
```

Operator setting: `CSI_ENABLE_ENCRYPTION: "true"`

---

## 4. Verification & Evidence Collection Procedure

### 4.1 Provisioning Test
1. Created PVC `encrypted-proof-pvc` using StorageClass `rook-ceph-block-encrypted`
2. PVC reached `Bound` state
3. Confirmed corresponding passphrase object appeared in Vault:

```bash
vault kv list rook/ceph-csi/
vault kv get rook/ceph-csi/<volume-id>
```

**Result:** Unique passphrase present under `rook/data/ceph-csi/`.

### 4.2 Runtime Attachment Test
1. Deployed test pod mounting the PVC
2. Volume attached to a worker node
3. On the node, confirmed LUKS device:

```bash
lsblk -f
cryptsetup status /dev/mapper/luks-*
cryptsetup luksDump /dev/rbdX
```

**Result:** Device reported as LUKS encrypted; passphrase successfully retrieved from Vault by CSI node plugin.

### 4.3 Access Control Test
- Authenticated to Vault using the CSI controller ServiceAccount token
- Confirmed the token received the `rook` policy
- Confirmed ability to create/read/delete objects only under the `ceph-csi/` path
- Confirmed unauthorized ServiceAccounts cannot retrieve the passphrase

### 4.4 Negative Test (optional)
- Raw RBD device (before LUKS open) contains no recognizable filesystem signature (random data)

---

## 5. Supporting Artifacts (to be retained)

| Artifact | Location / Command |
|----------|--------------------|
| StorageClass YAML | `rook-ceph-block-encrypted` |
| KMS ConfigMap | `rook-ceph-csi-kms-config` |
| Vault policy | `vault policy read rook` |
| Vault roles | `vault read auth/kubernetes/role/rook-ceph-csi` |
| Test PVC + Pod | `encrypted-proof-pvc` / `encryption-test-pod` |
| Vault secret listing | `vault kv list rook/ceph-csi/` |
| Node-level LUKS evidence | `cryptsetup luksDump` output |
| CSI logs (encryption events) | controller + nodeplugin logs |

---

## 6. Residual Risk / Notes

- Vault TLS verification is currently set to `vaultCAVerify: "false"` (self-signed / internal CA). Recommend enabling proper CA validation for production hardening.
- Root / highly privileged Vault tokens should be revoked after initial configuration; break-glass AppRole or equivalent administrative recovery method must be maintained.
- Key rotation of existing volume passphrases is not automatically performed; new volumes receive new keys. Rotation of existing volumes requires offline re-encryption procedures (out of scope for this implementation).

---

## 7. Conclusion

The implementation satisfies the intent of **NIST 800-171 3.13.11** and **3.13.16** for block storage encryption at rest:

- CUI/FCI data written to volumes using the encrypted StorageClass is protected by LUKS.
- Cryptographic keys are managed in an external KMS (Vault) with strong authentication and least-privilege access controls.
- Evidence of correct operation has been collected through provisioning, runtime attachment, and access-control tests.

**Control Status:** Implemented / Satisfied (with noted residual hardening items)

---
