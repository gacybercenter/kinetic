# LDAP, Keycloak, and Keystone Identity Federation

How LDAP, Keycloak, and OpenStack Keystone fit together in this repo, and the
one pillar tree (`pillar['ldap']`) that drives all three - so that adding
someone to a group is a single edit, not three.

## The short version

- **LDAP is the single source of truth** for users and groups (`ldap:users`,
  `ldap:groups` in pillar). Application bind DNs live separately under
  `ou=services` (`ldap:services`) — they are not people and are not group
  members.
- **Keycloak** authenticates humans (SSO/OIDC) against that same LDAP
  directory via its LDAP user federation - it does not own its own copy of
  user/group data.
- **Keystone** (OpenStack's identity service) has a domain (`rsc` by default)
  configured with a domain-specific **LDAP identity driver**, pointed at the
  same LDAP tree. Keystone project/role assignments are made against the
  **real LDAP groups** in that domain.
- When someone logs into Keystone via Keycloak SSO, Keystone maps the login
  directly onto that person's **already-existing real LDAP user account**
  (see "Why `type: local`?" below) - so their OpenStack permissions come from
  the exact same LDAP group membership as if they'd authenticated with a
  password directly against LDAP.

```mermaid
flowchart LR
    subgraph Pillar
        P["pillar['ldap']['groups']/['users']"]
    end

    subgraph LDAP
        L[(OpenLDAP)]
    end

    subgraph Keycloak
        K["Realm: rsc\nLDAP user federation"]
    end

    subgraph Keystone
        D["Domain: rsc\ndomain-specific LDAP driver"]
        PR["Projects + role assignments\n(on real LDAP groups)"]
    end

    subgraph Kubernetes
        RBAC["Role/RoleBinding\nClusterRole/ClusterRoleBinding"]
    end

    P -- "formulas/common/ldapadmin/prov.sls" --> L
    P -- "kubernetes: key" --> RBAC
    L -- "LDAP federation (reads only)" --> K
    L -- "LDAP identity driver (reads only)" --> D
    K -- "OIDC SSO login" --> D
    P -- "openstack: key\n(formulas/keystone/federation.sls)" --> PR
    D --> PR
```

Two separate Salt files consume the same `pillar['ldap']['groups']` /
`pillar['ldap']['users']` lists:

| File | Manages | Runs against |
|---|---|---|
| `formulas/common/ldapadmin/prov.sls` | LDAP users/groups themselves, plus Kubernetes RBAC (`kubernetes:` key) | Applied via a standalone orchestration (`orch/k8s-ldap-prov.sls`) - **does not** require Keystone to be up. |
| `formulas/keystone/federation.sls` | Keycloak identity provider/protocol/mapping in Keystone, plus OpenStack projects and role assignments on the real LDAP groups (`openstack:` key) | Gated on Keystone actually being reachable (`keystone_available` health-check state) before doing anything. |

They're kept separate specifically because `prov.sls` needs to work even
when OpenStack/Keystone isn't up yet (e.g. on a fresh cluster), while
`federation.sls`'s OpenStack API calls would just fail if run too early. See
[Applying a change](#applying-a-change) below for how to run both together
in one command.

## Pillar shape

Both files read from the same list-based pillar (this is also documented,
for the Kubernetes-RBAC half specifically, in
[`kinetic-k8s.md`](kinetic-k8s.md)):

```yaml
ldap:
  users:
    - uid: mdanielson
      cn: "Mark Danielson"
      sn: Danielson
      pass: "..."              # optional, GPG-encrypted in practice
      kubernetes: {...}        # optional - see kinetic-k8s.md

  groups:
    - cn: ncu
      members:
        - mdanielson           # uids of users defined above (or bare DNs)
      member_groups:
        - admins                # cns of other groups defined here (nested membership)
      kubernetes:               # optional - see kinetic-k8s.md
        roles:
          - namespace: default
            role: view
      openstack:                # optional - see below
        projects:
          - name: ncu            # optional; defaults to this group's cn verbatim
            description: "..."   # optional; defaults to "Project for <name>"
            domain: Default      # optional; defaults to Default
            roles: [member]      # optional; defaults to [member]

  services:                    # bind DNs under ou=services (not people)
    - cn: keycloak
      pass: "..."              # required on create; GPG-encrypted
```

### The `openstack:` key

Added per-group, drives `formulas/keystone/federation.sls`:

- `projects` may be a single mapping (shorthand for one project) **or** a
  list of mappings - both of these are equivalent:

  ```yaml
  openstack:
    projects:
      roles: [member]
  ```

  ```yaml
  openstack:
    projects:
      - roles: [member]
  ```

- `name` defaults to the group's `cn` **verbatim** (no character
  substitution) if omitted - this matters when the *same* project is
  referenced from more than one group (see the `admins` example below):
  whatever string you use for `name` must match exactly across every group
  that references that project, or you'll end up creating two different
  projects by mistake (this happened once with `gcr-persistent` vs a
  typo'd `gcr-presistent` in the `admins` group's list - worth
  double-checking project names any time you copy/paste a project list).
- `roles` (or singular `role`) is the list of Keystone role names to assign
  **this group** on the project. Defaults to `[member]`.
- Never creates OpenStack users, and never creates the LDAP groups
  themselves - `federation.sls` only creates/updates **projects** and
  **role assignments** on top of groups that `prov.sls` already provisions.

A single group can list many projects (typically your "admins" group,
granted `admin` on everything), and many groups can each grant themselves
`member` on their own like-named project - both patterns are deduplicated
correctly even when the same project name is referenced from multiple
groups (see `projects_map` in `federation.sls` if you're curious how).

```yaml
ldap:
  groups:
    - cn: admins
      members: [mdanielson]
      openstack:
        projects:
          - name: ncu
            roles: [admin]
          - name: gaaims
            roles: [admin]

    - cn: ncu
      members: []
      member_groups: [admins]
      openstack:
        projects:
          roles: [member]        # project name defaults to "ncu"
```

## Worked example: adding a member to a group

Using the group from the prompt:

```yaml
ldap:
  groups:
    - cn: ncu
      members:
        - mdanielson
      member_groups:
        - admins
      kubernetes:
        roles:
          - namespace: default
            role: view
```

Say you want to add a second person, `bcaldwell`, to the `ncu` group. Edit
the pillar:

```yaml
ldap:
  groups:
    - cn: ncu
      members:
        - mdanielson
        - bcaldwell            # <-- added
      member_groups:
        - admins
      kubernetes:
        roles:
          - namespace: default
            role: view
```

That's the only edit needed. What happens when this gets applied (see
[Applying a change](#applying-a-change)):

1. **LDAP** (`prov.sls`): `ldap_group_ncu` updates the `groupOfNames`
   `member` attribute in LDAP to include `bcaldwell`'s DN.
2. **Kubernetes RBAC** (`prov.sls`, same run): unaffected by this particular
   edit - the `kubernetes:` key here binds the `view` Role in `default` to
   the **group** `ncu` (not to individual members), so nothing needs to
   change on the Kubernetes side when membership changes; `bcaldwell`
   inherits access as soon as their Keycloak/OIDC token carries the `ncu`
   group claim.
3. **Keystone** (`federation.sls`): this particular `ncu` group entry has no
   `openstack:` key, so there is nothing for `federation.sls` to do for
   `ncu` directly. `bcaldwell` still gets OpenStack access indirectly
   through `member_groups: [admins]` - since `admins` already has an
   `openstack:` key with project role assignments, and `bcaldwell` is (or
   isn't, depending on your actual `admins` membership) a member of
   `admins` - the OpenStack-side effect always comes from a group's own
   (or nested, via `member_groups`) `openstack:` key, evaluated
   independently per group.

If instead you wanted `bcaldwell` (or the whole `ncu` group) to also get
OpenStack access to a project, you'd add an `openstack:` key to the `ncu`
group entry itself - see [The `openstack:` key](#the-openstack-key) above.

## Applying a change

Run the combined orchestration, which provisions LDAP/Kubernetes RBAC first,
then syncs Keystone projects/role assignments:

```bash
salt-run state.orchestrate orch.k8s-auth-sync pillar='{"k8s": "master-rsc-0"}'
```

(Replace `master-rsc-0` with whatever your `k8s` pillar value resolves to.)

This is intentionally **one command** - you never need to separately run
the `ldapadmin` and `keystone` formulas by hand for a simple membership
change. See `orch/k8s-auth-sync.sls`.

The name is deliberately generic (not `ldap-keystone-sync`) - LDAP should
stay the single source of truth for authorization wherever possible, and
this is the one place additional services get wired in if/when they need to
sync against that same `pillar['ldap']` data in the future.

If you only changed Kubernetes RBAC or LDAP data (no `openstack:` keys
touched), the Keystone step is still safe to run - it's fully idempotent
and will simply report no changes for anything that didn't move.

## Why `type: local` for the Keycloak/Keystone mapping?

`formulas/keystone/federation.sls` registers Keycloak as an identity
provider (`keystone_keycloak_idp`) and a federation mapping
(`keystone_keycloak_mapping`) in Keystone, so that OIDC logins from Keycloak
are accepted at all. The mapping rule looks like this:

```yaml
local:
  - user:
      type: local
      name: "{0}"
      domain:
        name: rsc
remote:
  - type: OIDC-preferred_username
```

`type: local` tells Keystone: *"don't create a separate ephemeral/shadow
identity for this login - resolve it directly onto an already-existing
Keystone user, matched by name + domain."* Since every Keycloak user here
is backed by (and named identically to) a real LDAP user already present in
the `rsc` domain, this means:

- No duplicate/shadow user is created for federated logins.
- Authorization comes from that **real** user's **real** LDAP group
  memberships and role assignments - the same ones a direct LDAP-password
  login would use. There is no separate "federated groups" concept to keep
  in sync.
- Keystone's `OIDC-preferred_username` claim (not the more common
  `HTTP_OIDC_PREFERRED_USERNAME` env var) is used deliberately - Apache's
  `mod_wsgi` drops the `HTTP_OIDC_PREFERRED_USERNAME` header before it
  reaches Keystone in this deployment, but the raw `OIDC-preferred_username`
  header is still readable directly.

### The road not taken: ephemeral/shadow federation + `HTTP_OIDC_GROUPS`

An earlier version of this mapping used Keystone's normal *ephemeral
federated user* flow instead - mapping the Keycloak `groups` claim
(`HTTP_OIDC_GROUPS`) onto Keystone groups via a `groups: "{1}"` local rule,
and creating a shadow/ephemeral user per login. This turned out to be
incompatible with domain-specific LDAP-backed groups: Keystone's federated
shadow-user group-membership tracking
(`ExpiringUserGroupMembership`) unconditionally writes a row with a foreign
key into the SQL `group` table for every resolved group id, on every
federated login - which fails with a `DB IntegrityError` for groups that
live in an LDAP-backed domain (they have no corresponding row in the SQL
`group` table).

`type: local` sidesteps this class of bug entirely, since that code path
only runs for ephemeral users. It's also simpler: one less layer of
group-claim mapping to keep in sync with the real LDAP groups.

## Service accounts (`ou=services`)

LDAP *drivers* (Keycloak user federation, Keystone's domain LDAP backend,
and anything else that binds to search/modify the directory) do **not**
use a person under `ou=users`. They bind as an account under:

```
ou=services,dc=rsc,dc=gacyberrange,dc=org
```

e.g. `cn=keycloak,ou=services,dc=rsc,dc=gacyberrange,dc=org`.

These are not `inetOrgPerson`. Typical entry:

```ldif
dn: cn=keycloak,ou=services,dc=rsc,dc=gacyberrange,dc=org
objectClass: top
objectClass: organizationalRole
objectClass: simpleSecurityObject
cn: keycloak
userPassword: {SSHA512}...
```

`organizationalRole` + `simpleSecurityObject` is enough to bind. They are
**not** group members, are not federated into Keycloak as users, and are
not Keystone users. Keycloak's `userObjectClasses`
(`inetOrgPerson, organizationalPerson`) only filters `usersDn`; it does
not have to match the bind DN.

Pillar (`ldap:services`) is consumed by
`formulas/common/ldapadmin/prov.sls` (`ldap.service_present`). `pass` is
set on create and not rotated by that state.

```yaml
ldap:
  services:
    - cn: keycloak
      description: "Keycloak LDAP user federation bind"
      pass: "..."    # GPG-encrypted
```

### ACLs

After `ou=services` exists, slapd ACLs on `olcDatabase={2}mdb,cn=config`
grant those bind DNs the rights they need (inserted at the front of
`olcAccess` so they win over slapd defaults):

| Rule | Target | `ou=services` | others |
|---|---|---|---|
| `{0}` | `userPassword,shadowLastChange` | write | self write, anonymous auth |
| `{1}` | ppolicy operational attrs | write | self read |
| `{2}` | `ou=users` subtree | write | self read |
| `{3}` | `ou=groups` subtree | read | none |

Group mapper is `READ_ONLY`, so services only need **read** on
`ou=groups`. OpenLDAP often reports a denied search base as LDAP 32
(`No Such Object`) — that is the usual cause of Keycloak
`NameNotFoundException` remaining name `ou=groups,...` at login.

**Apply the ACLs only after every LDAP driver already binds as
`ou=services` (or as the directory rootDN).** RootDN bypasses ACLs; a
person DN under `ou=users` will be locked out of user/group search once
`by * none` is in place.

Keycloak federation config should look like:

```yaml
config:
  usersDn: ou=users,dc=rsc,dc=gacyberrange,dc=org
  bindDn: cn=keycloak,ou=services,dc=rsc,dc=gacyberrange,dc=org
```

Search base stays `ou=users`; only the bind DN moves.

## OpenLDAP password policy (ppolicy)

Password *history* and related NIST-style constraints (lockout, min/max
age, min length) are enforced in **OpenLDAP**, not in Keycloak. Keycloak's
LDAP user federation writes `userPassword` into the directory; slapd's
`ppolicy` overlay then applies `pwdInHistory` / lockout / age on that
modify. A Keycloak-only `passwordHistory(N)` policy would not see the
directory's hashed history, and would not apply to anything that binds
LDAP directly (Keystone, CLI, other `ou=services` drivers).

This was originally applied **by hand** against `cn=config` / the data
tree (not yet driven from `formulas/common/ldapadmin/prov.sls`). The
related commit is `04919a22` (*Keep passwordHistory(N) on Keycloak policy
apply and add optional OpenLDAP ppolicy*) on
`nist-800-171-3.5.8-password-history`.

### What is in the directory

1. `ou=policies,dc=rsc,dc=gacyberrange,dc=org` — container for policy
   objects.
2. `cn=default,ou=policies,dc=rsc,dc=gacyberrange,dc=org` — the default
   `pwdPolicy` for human users. Current values:

   | Attribute | Value | Meaning |
   |---|---|---|
   | `pwdAttribute` | `userPassword` | Policy applies to password changes |
   | `pwdAllowUserChange` | `TRUE` | Users may change their own password |
   | `pwdCheckQuality` | `2` | Reject password if quality checks fail |
   | `pwdExpireWarning` | `604800` | Warn 7 days before expiry |
   | `pwdGraceAuthNLimit` | `5` | 5 grace authentications after expiry |
   | `pwdInHistory` | `24` | Reject reuse of the last 24 passwords |
   | `pwdLockout` | `TRUE` | Lock the account after too many failures |
   | `pwdLockoutDuration` | `600` | 10 minute lockout |
   | `pwdMaxAge` | `7776000` | 90 day max password age |
   | `pwdMaxFailure` | `5` | Lock after 5 failed binds |
   | `pwdMinAge` | `86400` | 1 day min age between changes |
   | `pwdMinLength` | `12` | Minimum password length |
   | `pwdMustChange` | `FALSE` | Do not force a change at next bind |
   | `pwdSafeModify` | `FALSE` | Old password not required on modify |

3. Overlay `olcOverlay={1}ppolicy,olcDatabase={2}mdb,cn=config` with
   `olcPPolicyDefault: cn=default,ou=policies,dc=rsc,dc=gacyberrange,dc=org`.
   Entries that do **not** set `pwdPolicySubentry` inherit this default.
   (The overlay index is `{1}` on this cluster, not `{0}` — look it up by
   name, do not assume the index.)

`pwdInHistory` / `pwdMinAge` apply on **password change**, not on the
existing hash. Reusing a previous password is rejected by design.

### Service accounts vs human users

Bind DNs under `ou=services` (e.g. `cn=keycloak,ou=services,...`) should
**not** inherit the human default (90-day expiry, history, lockout).
Point each service DN at a separate policy via `pwdPolicySubentry` (for
example `cn=service,ou=policies,...`) so `olcPPolicyDefault` does not
rotate or lock the Keycloak/Keystone bind passwords. `pwdPolicySubentry`
wins over the default for that entry.

Service-account ACLs on `olcDatabase={2}mdb,cn=config` (see
`ensure_services_acls` in `formulas/common/ldapadmin/prov.sls`) grant
`ou=services` write on `userPassword` so Keycloak can change user
passwords; ppolicy still evaluates history/lockout on that write.

### Recreating it (manual LDIF)

Bind as `cn=config` (same credentials as `LDAP_CONFIG_ADMIN_PASSWORD`).
`$params` is whatever `ldapadd`/`ldapmodify` flags you already use
(StartTLS, bind DN, host).

```ldif
dn: ou=policies,dc=rsc,dc=gacyberrange,dc=org
objectClass: top
objectClass: organizationalUnit
ou: policies
```

```ldif
dn: cn=default,ou=policies,dc=rsc,dc=gacyberrange,dc=org
objectClass: top
objectClass: person
objectClass: pwdPolicy
cn: default
sn: default
pwdAttribute: userPassword
pwdAllowUserChange: TRUE
pwdCheckQuality: 2
pwdExpireWarning: 604800
pwdGraceAuthNLimit: 5
pwdInHistory: 24
pwdLockout: TRUE
pwdLockoutDuration: 600
pwdMaxAge: 7776000
pwdMaxFailure: 5
pwdMinAge: 86400
pwdMinLength: 12
pwdMustChange: FALSE
pwdSafeModify: FALSE
```

```ldif
dn: olcOverlay={1}ppolicy,olcDatabase={2}mdb,cn=config
changetype: modify
replace: olcPPolicyDefault
olcPPolicyDefault: cn=default,ou=policies,dc=rsc,dc=gacyberrange,dc=org
```

Do not add a second `ppolicy` overlay if one already exists — slapd will
reject it (`overlay "ppolicy" already in list`). Do not `MOD_REPLACE` the
`olcOverlay` RDN on the existing entry.

### Keycloak side

Keycloak realm `password_policy` (length/complexity) is still useful for
*what the UI accepts*. Directory-side `pwdInHistory` is what actually
blocks reuse after a successful LDAP modify. Federation `editMode` must
be Keycloak's `WRITABLE` (one E) — `WRITEABLE` is rejected as HTTP 400
`Invalid provider type or no such provider` with no useful log line.

## Troubleshooting

- **"Group `['groupA', 'groupB']` has no entry in the backend" /
  malformed LDAP filter containing a Python list repr** - this was a
  symptom of the old ephemeral/`HTTP_OIDC_GROUPS` approach (see above) and
  should not occur with the current `type: local` mapping, since group
  claims are no longer parsed at all. If you see it again, check whether
  `mapping_rules` has been pillar-overridden back to a `groups:`-based rule.
- **User gets a valid Keycloak login but no OpenStack permissions** - check
  that the Keycloak username (the `preferred_username` claim) exactly
  matches the real LDAP `uid`/`cn` used to create that user in `rsc` via
  `prov.sls`. `type: local` requires an exact match; there's no fallback
  identity creation.
- **Two projects appear where you expected one** - almost always a
  copy/paste typo in a project `name:` across two different groups (see the
  `gcr-persistent`/`gcr-presistent` note above). `federation.sls` matches
  projects by exact string equality of `name`.
- **"found conflicting ID" when rendering `federation.sls`** - would mean
  two groups resolved to the same Salt state ID but with *different*
  literal project names or role sets in a way the dedup logic didn't
  expect; in practice this is now handled automatically (see `projects_map`
  in `federation.sls`), but if it recurs, check for inconsistent casing or
  whitespace in a `name:` field.
- Changed `ldap:groups`/`ldap:users` but nothing happened? Make sure you
  ran the orchestration (`orch/k8s-auth-sync.sls`), not just a
  `state.apply` of one formula - see
  [Applying a change](#applying-a-change).
- **Keycloak cannot change a password / "constraint violation" on
  modify** — often `pwdInHistory: 24` rejecting a previous password, or
  `pwdMinAge: 86400` blocking a second change inside 24 hours. That is
  the directory policy working; it is not an ACL failure. See
  [OpenLDAP password policy (ppolicy)](#openldap-password-policy-ppolicy).
- **Login `NameNotFoundException` remaining name
  `ou=groups,dc=rsc,dc=gacyberrange,dc=org`** — OpenLDAP often reports a
  denied search base as LDAP 32. The Keycloak bind DN under `ou=services`
  needs read on `ou=groups` (`ensure_services_acls`).

Last updated: October 2026
