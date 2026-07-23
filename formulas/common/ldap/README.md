# ldap Formula

Deploys OpenLDAP-HA using Helm and configures the LDAP directory structure using custom LDAP states and modules.

## Overview

This formula:
1. Deploys OpenLDAP-HA via Helm chart (`helm-openldap/openldap-stack-ha`)
2. Creates TLS certificates using the new `res-k8s:certs` structure
3. Configures LDAP directory (root DN, OUs, users, groups)
4. Sets up connection specs for SaltStack LDAP operations
5. Supports StartTLS for secure communication

The formula has been updated to use modern `k8s_helm` states and integrates with your certificate management changes.

## Updated Certificate Management

Certificates are now managed via the `res-k8s:certs` pillar structure (consistent with other formulas):

```yaml
res-k8s:
  certs:
    internal:
      name: ldap-tls
      issuer: cyberrange-ca-issuer
      commonname: ldap.rsc.gacyberrange.org
      dns_names:
        - ldap.rsc.gacyberrange.org
        - ldap-int.rsc.gacyberrange.org
```

**Note**: The certificate state now uses `k8s.certmanager_certificate_present` with the new pillar structure.

## Pillar Structure Summary

**Key sections to configure:**

- `ldap:namespace`, `ldap:version` - deployment settings
- `ldap:values` - Helm chart values (replicaCount, image, persistence, replication, ingress, etc.)
- `res-k8s:certs` - Certificate configuration (replaces old `ldap:cert` structure)
- `ldap:admin-user` - admin credentials (GPG encrypted)
- `ldap:root_dn` - root DN and organization info
- `ldap:orgunits` - organizational units to create
- `ldap:users` and `ldap:groups` - users and groups with GPG-encrypted passwords
- `ldap:pull_secret` - container registry credentials
- `ldap:logger-cm` - FluentBit/OpenSearch logging configuration

See the attached pillar files for complete structure. Passwords should be GPG-encrypted.

## Usage

```yaml
include:
  - /formulas/common/ldap
```

## Orchestration

Use the orchestration script `orch/k8s-authldap.sls` to deploy the complete solution:

```bash
salt-run state.orchestrate orch.k8s-authldap
```

This handles node preparation, LDAP deployment, certificate creation, and directory initialization in the correct order.

## Key Components

### 1. OpenLDAP-HA Deployment
- Uses modern `k8s_helm.helm_release_present` with pillar-driven values
- Creates pull secrets for container registry access
- Sets up replication (3 replicas by default)
- Configures persistence and logging (FluentBit to OpenSearch)

### 2. Certificate Management
- Uses the new `res-k8s:certs` structure with `k8s.certmanager_certificate_present`
- Supports both internal CA and Let's Encrypt issuers
- Creates Kubernetes secrets for the certificates

### 3. LDAP Directory Initialization
- Creates connection spec with StartTLS support using `ldap.connect_spec_present`
- Sets up root DN with proper object classes using `ldap.root_dn_present`
- Creates organizational units from pillar using `ldap.ou_present`
- Creates users and groups with proper attributes and memberships using `ldap.user_present` and `ldap.group_present`

### 4. Security
- Uses StartTLS for all LDAP communications
- GPG-encrypted passwords in pillar
- Proper RBAC and service account configuration

## Dependencies

- `formulas/common/helm` (via `k8s_helm` states)
- `formulas/common/k8s` (namespace, secret, certmanager, configmap states)
- `ldap` state and `ldap_utils` execution modules
- cert-manager with appropriate issuers configured
- OpenSearch/FluentBit for logging (optional but configured)

## Files

- `init.sls` — Main entrypoint
- `install.sls` — Helm deployment, certificates, secrets, and ConfigMaps (updated to use modern states)
- `configure.sls` — LDAP directory initialization (unchanged - uses existing ldap states)
- `README.md` — This file

## Related

- `common/k8s-certmanager`
- `common/k8s`
- `_modules/ldap_utils.py`
- `_states/ldap.py`
- `orch/k8s-authldap.sls`

**Last updated**: July 2025
