# kinetic-k8s Module

SaltStack execution module (`kinetic_k8s`) and state module (`k8s`) for managing Kubernetes resources directly via the `kubernetes` Python client.

This is a large, general-purpose module covering many resource types (Secrets, ConfigMaps, PVs/PVCs, Custom Resources, etc.). This document does not attempt to cover the whole module yet - it currently tracks the RBAC-related additions made to support LDAP/OIDC-group-driven Kubernetes permissions (Keycloak groups -> Kubernetes RBAC).

## RBAC functions (added 2026-08-06)

Motivation: LDAP group membership is synced into Keycloak (via LDAP group mappers) and surfaced in the OIDC "groups" claim during Kubernetes API authentication (OIDC auth). These functions let Salt manage the Kubernetes-side `Role`/`ClusterRole`/`RoleBinding`/`ClusterRoleBinding` objects needed to turn that claim into real permissions, keyed off Group subjects.

All functions return `{"success": bool, "updated": bool, "message": str}` and are idempotent (a no-op run reports `updated: False`), matching the conventions used elsewhere in this module (e.g. `clusterrolebinding_present`).

### Execution module (`_modules/kinetic-k8s.py`)

| Function | Purpose |
|---|---|
| `role_present(namespace, name, rules)` | Create/update a namespaced `Role`. |
| `role_absent(namespace, name)` | Delete a namespaced `Role`. |
| `clusterrole_present(name, rules)` | Create/update a `ClusterRole`. |
| `clusterrole_absent(name)` | Delete a `ClusterRole`. |
| `rolebinding_present(namespace, name, role_ref, role_ref_kind="Role", groups=None, users=None, service_accounts=None, subjects=None)` | Create/update a namespaced `RoleBinding` with arbitrary subject kinds. |
| `rolebinding_absent(namespace, name)` | Delete a namespaced `RoleBinding`. |
| `clusterrolebinding_group_present(name, cluster_role, groups=None, users=None, service_accounts=None, subjects=None)` | Create/update a `ClusterRoleBinding` with arbitrary subject kinds (Group/User/ServiceAccount). |
| `clusterrolebinding_group_absent(name)` | Delete a `ClusterRoleBinding`. |

**Note:** `clusterrolebinding_present`/`clusterrolebinding_absent` (pre-existing, used by `formulas/common/k8s-vault/configure.sls`) are narrowly scoped to `ServiceAccount` subjects only and were **not modified**. `clusterrolebinding_group_present`/`clusterrolebinding_group_absent` are new, separate functions for bindings that need `Group` and/or `User` subjects (e.g. driven by an OIDC "groups" claim).

Rule dicts passed to `role_present`/`clusterrole_present` support the keys: `api_groups`, `resources`, `verbs`, `resource_names`, `non_resource_urls` (all optional except `verbs`).

```
rules:
  - api_groups: [""]
    resources: ["pods", "pods/log"]
    verbs: ["get", "list", "watch"]
```

Subject convenience kwargs shared by `rolebinding_present` and `clusterrolebinding_group_present`:

- `groups`: list of group names -> bound as `kind: Group`, `apiGroup: rbac.authorization.k8s.io`.
- `users`: list of usernames -> bound as `kind: User`, `apiGroup: rbac.authorization.k8s.io`.
- `service_accounts`: list of `"namespace:serviceaccount"` strings, or bare names (defaulting to the binding's own namespace for `rolebinding_present`) -> bound as `kind: ServiceAccount` (no `apiGroup`).
- `subjects`: raw list of subject dicts for full control (e.g. `[{"kind": "Group", "name": "k8s-admins"}]`), merged with the convenience kwargs above.

### State module (`_states/k8s.py`)

Matching state wrappers: `k8s.role_present`, `k8s.role_absent`, `k8s.clusterrole_present`, `k8s.clusterrole_absent`, `k8s.rolebinding_present`, `k8s.rolebinding_absent`, `k8s.clusterrolebinding_group_present`, `k8s.clusterrolebinding_group_absent`.

```yaml
k8s_admins_clusterrolebinding:
  k8s.clusterrolebinding_group_present:
    - name: k8s-admins-binding
    - cluster_role: cluster-admin
    - groups:
      - k8s-admins

monitoring_viewers_rolebinding:
  k8s.rolebinding_present:
    - name: viewers-binding
    - namespace: monitoring
    - role_ref: view
    - role_ref_kind: ClusterRole
    - groups:
      - k8s-viewers
```

### Important gotcha: Keycloak group claim format

Keycloak's default "Group Membership" protocol mapper emits the **full group path** (e.g. `/k8s-admins`, with a leading slash) in the OIDC `groups` claim, not just the bare group name - unless "Full group path" is disabled in the mapper configuration. The Kubernetes RoleBinding/ClusterRoleBinding `Group` subject name must match **exactly** what appears in that claim, so either:

- Disable "Full group path" on the Keycloak group mapper so it emits bare group names (e.g. `k8s-admins`), or
- Use the full path (e.g. `/k8s-admins`) as the `groups` value passed to these states/functions.

### Known upstream client quirk

The installed `kubernetes` Python client's generated `V1PolicyRule` model exposes the non-resource-URL field as `non_resource_ur_ls` (not `non_resource_urls`) due to a long-standing codegen bug. `_build_policy_rules`/`_normalize_rule` in `kinetic-k8s.py` handle this internally - the rule-dict API exposed to Salt states still uses the correctly-spelled `non_resource_urls` key.

## Planned pillar shape (not yet implemented)

The goal is a pillar-driven formula (see "Still to do" below) that reads an optional `kubernetes` sub-key on entries in the existing `pillar['ldap']['groups']` and `pillar['ldap']['users']` lists - the same lists already consumed by `formulas/common/ldapadmin/prov.sls` (`ldap.group_present` / `ldap.user_present`) - and generates the RBAC states documented above. This keeps "who has access to what" declared in one place, alongside the existing LDAP identity definitions, instead of a separate RBAC pillar tree.

`ldap:groups` entries would drive Group-subject bindings (`clusterrolebinding_group_present` / `rolebinding_present`), and `ldap:users` entries would drive User-subject bindings, for cases where an individual needs access outside of any group. Both `groups` and `users` remain plain lists (matching the shape `ldap.group_present`/`ldap.user_present` already expect via `cn`/`uid`), with an added `kubernetes` key per entry:

```yaml
ldap:
  groups:
    - cn: k8s-admins
      description: Kubernetes cluster administrators
      members:
        - jdoe
        - asmith
      kubernetes:
        cluster_roles:
          - cluster-admin

    - cn: k8s-viewers
      description: Read-only access to select namespaces
      members:
        - bwayne
      kubernetes:
        roles:
          - namespace: default
            role: view
          - namespace: monitoring
            role: view
        custom_roles:
          - name: pod-log-reader
            namespace: default
            rules:
              - api_groups: [""]
                resources: ["pods", "pods/log"]
                verbs: ["get", "list", "watch"]

  users:
    - uid: jdoe
      cn: John Doe
      sn: Doe
      kubernetes:
        cluster_roles:
          - cluster-admin

    - uid: bwayne
      cn: Bruce Wayne
      sn: Wayne
      kubernetes:
        roles:
          - namespace: gotham-app
            role: edit
```

Notes on this planned shape:

- `cluster_roles`: list of `ClusterRole` names to bind cluster-wide via `clusterrolebinding_group_present` (Group subject for entries under `ldap:groups`, User subject for entries under `ldap:users`).
- `roles`: list of `{namespace, role}` pairs, each becoming a `rolebinding_present` binding an existing `Role`/`ClusterRole` in that namespace.
- `custom_roles`: list of full role definitions (`name`, optional `namespace` - omit for a `ClusterRole` - and `rules`), for cases where an existing Role/ClusterRole doesn't already cover the needed permissions. These would be created via `role_present`/`clusterrole_present` before the corresponding binding.
- Because Keycloak's OIDC "groups" claim may emit the full group path (see the gotcha above), the formula will likely need a per-group override (e.g. `k8s_group_name: /k8s-admins`) for cases where "Full group path" isn't disabled on the Keycloak mapper.

This shape is illustrative and not final - it will be refined once the actual formula is built.

## Still to do

- Build the pillar-driven formula (e.g. `formulas/common/k8s-rbac/`) implementing the shape above.
- Full module documentation covering the rest of `kinetic-k8s`/`k8s` (Secrets, ConfigMaps, PV/PVC, custom resources, etc.).

Last updated: August 2026
