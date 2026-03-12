# Documentation: Creating and Provisioning OpenLDAP-HA with SaltStack

This document provides a comprehensive guide to creating and provisioning an OpenLDAP-HA (High Availability) setup using SaltStack states, modules, and pillar data. The setup leverages custom SaltStack modules (`ldap_utils.py`) and states (`ldap.py`) to manage LDAP directory structures, including root DN, organizational units (OUs), users, and groups. The provisioning is driven by pillar files for configuration and a state file (`configure.sls`) for orchestration.

The guide assumes a Kubernetes environment (based on pillar values like `replicaCount` and service configurations) and focuses on the LDAP directory initialization. It is based on the provided files and can be extended for production use.

## Overview

OpenLDAP-HA is provisioned as a replicated service (e.g., 3 replicas) using a Helm chart or direct Kubernetes manifests, with SaltStack handling the LDAP directory configuration (e.g., creating root DN, OUs, users, and groups). Key components include:

- **Pillar Files**: Define LDAP structure (root DN, OUs, users, groups) and deployment settings (e.g., images, secrets, persistence).
- **Execution Module (`ldap_utils.py`)**: Low-level functions for LDAP operations like checking existence (`dn_exists`), creating/updating root DN, OUs, users, and groups.
- **State Module (`ldap.py`)**: High-level states (e.g., `user_present`, `group_present`) that ensure desired LDAP state using the execution module.
- **State File (`configure.sls`)**: Orchestrates the creation of the LDAP connection spec, root DN, OUs, users, and groups, with dependencies for order.

This setup ensures idempotency: Running the states multiple times won't recreate existing entries but will update them if needed.

## Prerequisites

- **SaltStack Installation**: Salt Minion and Master set up, with the provided modules and states synced to the minion (e.g., in `/srv/salt/_modules/` and `/srv/salt/_states/`).
- **LDAP Server**: An OpenLDAP server (e.g., deployed via Helm with the provided pillar values) accessible via the URL in `configure.sls` (e.g., `ldap://<common_name>`).
- **Dependencies**:
  - Python libraries: `python-ldap` for LDAP operations, `re` for regex (used in states).
  - Pillar data: Encrypted with GPG (e.g., passwords in `ldap-users.sls`).
  - Kubernetes/Helm: For deploying OpenLDAP-HA (based on pillar values like `replicaCount: 3`, `image.repository`).
- **Permissions**: The bind DN in `configure.sls` (e.g., `cn=admin,dc=rsc,dc=gacyberrange,dc=org`) must have admin rights to create/modify entries.
- **Tools**: GPG for decrypting pillar values, regex support in Python.

## Pillar Configuration

Pillar files define the LDAP structure and deployment settings. They are included in `ldap.sls` and used in states.

### `ldap.sls` (Main Pillar)
This file includes other pillars and defines deployment settings for OpenLDAP-HA.

- **Key Sections**:
  - `include`: Loads users and OUs from other files.
  - `admin-user`: Admin credentials (GPG-encrypted).
  - `ldap`: Deployment values (e.g., namespace, version, pull secrets, logging config with FluentBit, replication settings, persistence, ingress).

Example excerpt (decrypted for illustration):
```
ldap:
  namespace: keycloak
  version: 4.3.3
  admin-user:
    name: admin
    password: <decrypted_password>
  pull_secret:
    name: ldap-repo-secret
    repo: registry.gitlab.com
    user: build-token
    key: <decrypted_key>
  values:
    replicaCount: 3
    image:
      repository: gacybercenter/open/kinetic/containers/openldap
      tag: "latest"
    persistence:
      enabled: true
    replication:
      enabled: true
    # ... (other settings like logging, ingress, etc.)
```

### `ldap-ous.sls` (Organizational Units)
Defines the root DN and OUs.

Example:
```
ldap:
  root_dn:
    dn: "dc=rsc,dc=gacyberrange,dc=org"
    o: "Georgia Cyber Range GovCloud and Research"
  orgunits:
    - name: users
      dc: rsc
    - name: groups
      dc: rsc
    - name: workstations
      dc: rsc
    - name: servers
      dc: rsc
```

### `ldap-users.sls` (Users and Groups)
Defines users and groups with GPG-encrypted passwords.

Example:
```
ldap:
  users:
    - name: "Mark Danielson"
      sn: Danielson
      uid: mdanielson
      pass: <GPG-encrypted_password>
    - name: "Marc Danielson"
      sn: Danielson
      uid: mdanielson1
      pass: <GPG-encrypted_password>
  groups:
    - name: admins
      members:
        - mdanielson
        - mdanielson1
```

## Execution Module: `ldap_utils.py`

This module provides functions for LDAP operations. Key functions for provisioning:

- `dn_exists`: Checks if a DN exists and attributes match.
- `create_root_dn` / `update_root_dn`: Manage the root DN.
- `create_ou` / `update_ou`: Manage OUs.
- `create_user` / `update_user`: Manage users (with fixed objectClasses and attributes).
- `create_group` / `update_group`: Manage groups (with members).

Functions return standardized dicts: `{'result': bool, 'comment': str, 'changes': dict}`.

## State Module: `ldap.py`

This module defines states that use `ldap_utils.py` to ensure LDAP entities exist.

- `root_dn_present`: Ensures root DN with attributes.
- `ou_present`: Ensures OUs (single or multiple via pillar loop).
- `user_present`: Ensures users (creates/updates with fixed attributes, password on create only).
- `group_present`: Ensures groups (creates/updates with members).

States are idempotent and support test mode.

## State File: `configure.sls`

This SLS file orchestrates provisioning:

- Creates LDAP connection spec.
- Sets up root DN.
- Loops through pillar to create OUs.
- Loops through pillar to create users (under `ou=users`).
- Loops through pillar to create groups (under `ou=groups`).

Example excerpt:
```
# Ensure Organizational Units
{% for ou in pillar['ldap']['orgunits'] %}
ensure_ou_{{ ou.name }}:
  ldap.ou_present:
    - name: ou={{ ou.name }}
    - base_dn: {{ pillar['ldap']['root_dn']['dn'] }}
    - spec_name: ldap_config_connection
    - require:
      - ldap: ensure_root_dn
{% endfor %}

# Ensure users
{% for user in pillar['ldap']['users'] %}
ensure_user_{{ user.uid }}:
  ldap.user_present:
    - name: ensure_user_{{ user.uid }}
    - spec_name: ldap_config_connection
    - base_dn: ou=users,{{ pillar['ldap']['root_dn']['dn'] }}
    - uid: {{ user.uid }}
    - cn: {{ user.uid }}
    - sn: {{ user.sn }}
    - description: {{ user.name }}
    - password: {{ user.pass }}
    - require:
      - ldap: ensure_ou_users
{% endfor %}

# Ensure groups
{% for group in pillar['ldap']['groups'] %}
ensure_group_{{ group.name }}:
  ldap.group_present:
    - name: ensure_group_{{ group.name }}
    - spec_name: ldap_config_connection
    - base_dn: ou=groups,{{ pillar['ldap']['root_dn']['dn'] }}
    - cn: {{ group.name }}
    - description: {{ group.get('description', '') }}
    - members:
      {% for member in group.members %}
      - cn={{ member }},ou=users,{{ pillar['ldap']['root_dn']['dn'] }}
      {% endfor %}
    - require:
      - ldap: ensure_ou_groups
{% endfor %}
```

## Step-by-Step Provisioning Guide

1. **Setup Pillar Files**:
   - Configure `ldap.sls`, `ldap-ous.sls`, `ldap-users.sls` with your values (encrypt sensitive data with GPG).
   - Apply pillars to the minion: `salt '*' pillar.refresh`.

2. **Deploy OpenLDAP-HA Infrastructure**:
   - Use the pillar values in `ldap.sls` to deploy via Helm or Kubernetes (e.g., `helm install openldap-ha openldap-chart --values ldap.sls`).
   - This sets up replicas, persistence, logging (FluentBit to OpenSearch), replication, and ingress.

3. **Sync Modules and States**:
   - Place `ldap_utils.py` in `/srv/salt/_modules/` and `ldap.py` in `/srv/salt/_states/`.
   - Sync to minion: `salt '*' saltutil.sync_all`.

4. **Apply Configuration State**:
   - Run: `salt '*' state.apply formulas.common.ldap.configure`.
   - This:
     - Creates the connection spec.
     - Ensures root DN.
     - Creates OUs from pillar.
     - Creates users from pillar (with dependencies on OUs).
     - Creates groups from pillar (with members referencing users).

5. **Verify**:
   - Use `ldapsearch` to check entries (e.g., `ldapsearch -ZZ -x -H ldap://<server> -b "dc=rsc,dc=gacyberrange,dc=org" "(objectClass=*)"`).
   - Check Salt output for `result: true` and changes.

## Security Notes: Using StartTLS

StartTLS is required for communication with the OpenLDAP server to protect against eavesdropping and man-in-the-middle attacks. It upgrades a plain LDAP connection to an encrypted one using TLS.

- **Requirement**: Always use StartTLS when connecting to the server. The connection spec in `configure.sls` enables it with `starttls: True`.
- **ldapsearch Examples**:
  - Basic query with StartTLS: `ldapsearch -x -H ldap://<server> -b "dc=rsc,dc=gacyberrange,dc=org" "(objectClass=*)" -ZZ`
    - `-ZZ`: Enforces StartTLS and fails if it can't be established.
  - With bind credentials: `ldapsearch -x -H ldap://<server> -D "cn=admin,dc=rsc,dc=gacyberrange,dc=org" -W -b "dc=rsc,dc=gacyberrange,dc=org" "(objectClass=*)" -ZZ`
  - If using LDAPS (port 636), StartTLS isn't needed, but verify the URL in the spec (e.g., `ldaps://<server>`).

For troubleshooting, if StartTLS fails, check TLS settings in pillar (e.g., `tls_cacert`, certificate validity).

## Troubleshooting

- **Common Errors**:
  - "TLS confidentiality required": TLS is required, if using ldap-utils (ldapsearch etc) add -Z or -ZZ. 
  - "No such object": DN doesn't exist—check existence logic in `dn_exists`.
  - "Already exists": Handled as success in states.
  - Permission issues: Verify bind DN credentials.
- **Logs**: Check Salt minion logs for debug info (set `log_level: debug` in minion config).
- **Test Mode**: Run with `--test=true` to simulate without changes.

```
