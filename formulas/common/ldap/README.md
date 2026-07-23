# ldap Formula

Deploys OpenLDAP-HA using Helm and configures the LDAP directory structure using custom LDAP states and modules.

## Overview

This formula:
1. Deploys OpenLDAP-HA via Helm chart (`helm-openldap/openldap-stack-ha`)
2. Creates TLS certificates using cert-manager
3. Configures LDAP directory (root DN, OUs, users, groups)
4. Sets up connection specs for SaltStack LDAP operations
5. Supports StartTLS for secure communication

The formula uses modern `k8s_helm` states and the existing `ldap` state/module infrastructure.

## Pillar Structure Summary

**Key sections to configure:**

- `ldap:namespace`, `ldap:version` - deployment settings
- `ldap:values` - Helm chart values (replicaCount, image, persistence, replication, ingress, etc.)
- `ldap:cert` - certificate configuration (common_name, dns_names, ip_addresses, issuer)
- `ldap:admin-user` - admin credentials (GPG encrypted)
- `ldap:root_dn` - root DN and organization info
- `ldap:orgunits` - organizational units to create
- `ldap:users` and `ldap:groups` - users and groups with GPG-encrypted passwords
- `ldap:pull_secret` - container registry credentials
- `ldap:logger-cm` - FluentBit/OpenSearch logging configuration

See the attached pillar files (`ldap.sls`, `ldap-ous.sls`, `ldap-users.sls`) for complete structure.

**Note**: Passwords and sensitive data should be GPG-encrypted in pillar.

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
- Uses `k8s_helm.helm_release_present` with pillar-driven values
- Creates pull secrets for container registry access
- Sets up replication (3 replicas by default)
- Configures persistence and logging (FluentBit to OpenSearch)

### 2. Certificate Management
- Uses `k8s.certmanager_certificate_present` for TLS certificates
- Supports both internal CA and Let's Encrypt issuers
- Creates Kubernetes secrets for the certificates

### 3. LDAP Directory Initialization
- Creates connection spec with StartTLS support
- Sets up root DN with proper object classes
- Creates organizational units from pillar
- Creates users and groups with proper attributes and memberships
- Uses the `ldap.*_present` states for idempotent management

### 4. Security
- Uses StartTLS for all LDAP communications
- Supports mTLS (though not currently implemented in states)
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
- `install.sls` — Helm deployment, certificates, secrets, and ConfigMaps
- `configure.sls` — LDAP directory initialization (root DN, OUs, users, groups)
- `README.md` — This file

## Related

- `common/k8s-certmanager`
- `common/k8s`
- `_modules/ldap_utils.py`
- `_states/ldap.py`

**Last updated**: July 2025
