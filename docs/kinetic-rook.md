# kinetic-rook Module

SaltStack execution and state modules for managing Rook Ceph Custom
Resources (CRs) directly against the Kubernetes API - complementing
`kinetic-helm` (which manages the Rook *operator* itself via its Helm
chart) by managing the Ceph resources Rook then reconciles.

## Features

- Manage `CephCluster`, `CephBlockPool`, `CephObjectStore`, and
  `CephObjectStoreUser` custom resources, plus RBD `StorageClass` objects
- Idempotent `*_present` semantics: compares the desired spec against the
  live resource and only creates/updates when something actually differs
- RGW (Ceph Object Gateway) user/subuser management with **no
  `radosgw-admin` CLI and no manually-signed Admin Ops API calls** -
  users go through Rook's own CRD, subusers go through the Ceph Mgr
  Dashboard's REST API (simple JWT auth, no AWS SigV4 signing dependency)

## Why not just call the RGW Admin Ops API directly?

Early iterations of RGW user/subuser management in this module signed
requests directly against Ceph's [RGW Admin Ops
API](https://docs.ceph.com/en/latest/radosgw/adminops/) using AWS
SigV4 (`requests-aws4auth`). That was dropped in favor of two better-fit
approaches once it became clear this environment is Kubernetes/Rook-native
throughout:

- **Users**: Rook's `CephObjectStoreUser` CRD lets Rook's own operator
  create the RGW user and drop the resulting S3 keys into a Kubernetes
  Secret - no admin credentials, no signing, and it matches every other
  CR-driven pattern already in this module.
- **Subusers**: Rook's CRD has no subuser field, and the raw Admin Ops API
  still needs SigV4 signing (an extra `requests-aws4auth` dependency). The
  [Ceph Mgr Dashboard REST
  API](https://docs.ceph.com/en/quincy/mgr/ceph_api/#rgwuser) exposes the
  same subuser operations behind simple username/password → JWT bearer-token
  auth, so `rgw_subuser_present` uses that instead - just `requests`, no
  extra pip dependency.
- **Swift "temp URL key"** (used by e.g. Glance to generate time-limited
  signed download URLs) is not exposed by *either* API - only by
  `radosgw-admin` CLI, or (as used elsewhere in this repo, see
  `kinetic-openstack`'s `account_temp_url_key_present`) the native Swift
  account-metadata API. It's out of scope for this module entirely.

## Usage Examples

### CephCluster

```yaml
rook_cluster:
  rook.ceph_cluster_present:
    - name: rook-ceph
    - namespace: rook-ceph
    - ceph_version: quay.io/ceph/ceph:v18.2.4
    - use_all_nodes: True
    - use_all_devices: False
    - device_filter: "^sd."
    - network_provider: host
    - dashboard_enabled: True
    - monitoring_enabled: True
    - toolbox_enabled: True
    - resources_pillar: res-k8s:rook:resources
    - placement_pillar: res-k8s:rook:placement
```

Pass a complete `spec` dict instead of the individual keyword args for full
control over the `CephCluster` (it overrides everything else):

```yaml
rook_cluster:
  rook.ceph_cluster_present:
    - name: rook-ceph
    - namespace: rook-ceph
    - spec:
        cephVersion:
          image: quay.io/ceph/ceph:v18.2.4
        dataDirHostPath: /var/lib/rook
        storage:
          useAllNodes: true
          useAllDevices: false
          deviceFilter: "^sd."
```

Notes:
- `placement_pillar`/`resources_pillar` read a pillar tree shaped like
  Rook's own `placement`/`resources` spec fields. If a placement component
  is named `node`, it's automatically remapped to `all` (Rook's
  convention for "apply to every component").
- `network_provider: host` supports `public_network`/`cluster_network` as
  CIDR ranges (string or list) via `spec.network.addressRanges`.
  Setting `cluster_network` without `host` provider switches to Multus,
  expecting `"namespace/nadname"` values (bare NAD names are assumed to be
  in the `default` namespace).

### CephBlockPool

```yaml
rook_general_pool:
  rook.ceph_blockpool_present:
    - name: general
    - namespace: rook-ceph
    - failure_domain: host
    - replicated_size: 3
```

### RBD StorageClass

```yaml
rook_ceph_block_sc:
  rook.storageclass_present:
    - name: rook-ceph-block
    - provisioner: rook-ceph.rbd.csi.ceph.com
    - cluster_id: rook-ceph
    - reclaim_policy: Delete
    - volume_binding_mode: Immediate
    - allow_volume_expansion: True
```

Pass `parameters` to fully override the default CSI secret/pool
parameters, or `spec` for complete control.

### CephObjectStore (RGW)

```yaml
deploy_ceph_object_store:
  rook.ceph_object_store_present:
    - name: rsc-object-store
    - namespace: rook-ceph
    - replicas: 3
    - port: 80
    - gateway_instances: 2
    - enable_s3_api: true
    - enable_swift_api: true
    - swift_url_prefix: "swift"
    - preserve_pools_on_delete: true
    - auth_keystone: true
    - keystone_url: "http://keystone-api.openstack.svc.cluster.local:5000"
    - keystone_accepted_roles: [admin, member, service]
    - keystone_implicit_tenants: "swift"
    - keystone_service_user_secret_name: "keystone-admin"
    - enable_apis: [s3, swift, swift_auth]
    - rgw_config:
        rgw_request_timeout: "900"
        rgw_op_thread_timeout: "900"
        rgw_thread_pool_size: "8"
    - rgw_command_flags:
        rgw-frontends: "beast port=80 request_timeout_ms=300000"
    - gateway_resources:
        limits:
          cpu: "500m"
          memory: "512Mi"
        requests:
          cpu: "200m"
          memory: "256Mi"
```

Notes:
- `enable_apis` sets `spec.protocols.enableAPIs`, which is a **separate**
  field from the per-protocol `enabled` flags (`enable_s3_api`,
  `enable_swift_api`) - Rook does not reliably enable `swift_auth`
  alongside `swift` on its own, so if you don't pass `enable_apis`
  explicitly, this module derives a sensible default
  (`["s3"]`/`["swift", "swift_auth"]`) from those flags for you.
- `rgw_config` is a generic dict merged into `spec.gateway.rgwConfig`
  (raw `ceph.conf` `[client.rgw.*]` key/value pairs) on top of whatever
  Keystone-related keys `auth_keystone`/`rgw_keystone_*`/`debug_rgw`
  produce. Use it for anything not already covered by a named parameter
  (`rgw_request_timeout`, `rgw_thread_pool_size`, `rgw_max_put_size`,
  etc.) rather than waiting for a dedicated keyword argument.
- `rgw_command_flags` sets `spec.gateway.rgwCommandFlags` - extra
  command-line flags passed to the `radosgw` process itself (e.g.
  overriding the `beast` frontend's `request_timeout_ms`).
- If the live `CephObjectStore`'s spec differs from the desired one, this
  state **deletes and recreates** it rather than patching in place (Rook
  applies many of these fields only at creation time). The delete is
  fire-and-forget - expect a second state run to actually recreate the
  resource once Rook finishes tearing down the old one. Watch
  `kubectl -n rook-ceph get cephobjectstore -w` during a spec change if
  you want to confirm it comes back cleanly, especially with
  `preserve_pools_on_delete: false`.

### CephObjectStoreUser (RGW user, no admin credentials needed)

```yaml
glance_rgw_user:
  rook.ceph_object_store_user_present:
    - name: glance
    - namespace: rook-ceph
    - store: rsc-object-store
    - display_name: glance
    - capabilities:
        user: "*"
        buckets: "*"
    - require:
      - rook: deploy_ceph_object_store
```

Rook creates the RGW user itself and writes the resulting S3 access/secret
key pair into a Kubernetes Secret named
`rook-ceph-object-user-<store>-<name>` in `namespace` - no signing, no
admin identity, nothing else to provision first.

Notes:
- `capabilities` can only be applied at **creation** time (a Rook/Ceph
  limitation) - changing them later requires deleting and recreating the
  `CephObjectStoreUser`, which this state does automatically if the spec
  no longer matches (same delete-then-recreate-on-next-run behavior as
  `ceph_object_store_present`).
- Does **not** support subusers or a Swift temp-url-key - see below and
  the "Why not..." section above.

### OIDC provider (IAM query API, not `radosgw-admin oidc`)

`radosgw-admin oidc provider` is newer than the Ceph this cluster runs.
`CreateOpenIDConnectProvider` is the older, documented API and is what
`oidc_provider_present` calls (signed as service `iam`, stdlib SigV4, no
`requests-aws4auth`). See https://docs.ceph.com/en/reef/radosgw/oidc/.
The LDAP group to Keycloak token to RGW role path for the ss3 store is
[`ldap-keycloak-rgw.md`](ldap-keycloak-rgw.md).

The provider is keyed by the issuer URL with the scheme stripped, not by
the friendly name. STS looks it up the same way from the token `iss`, so
`rgw_role_present` must be given `issuer_url` or the trust policy will not
match. `evaluating policy for op: 144 returned deny/pass` is that check
failing: op 144 is `sts:AssumeRoleWithWebIdentity`. RGW copies the JWT
`aud` claim into `<provider>:app_id`, but a Keycloak access token sets
`aud` to `account` unless the client has an `oidc-audience-mapper` that
adds the client id to the access token. The object-store formula creates
that mapper and conditions the role on `:app_id`. Group membership is
checked only at assume-role (`<issuer>:groups`). The condition must match
the claim exactly. Keycloak emits the bare LDAP group name (`ss3-admins`),
so `group_prefix` defaults to empty. Pass `group_prefix: "/"` only if a
mapper still emits the full path. The session does not carry the JWT, so a later S3 call
cannot be filtered by group. Give each group its own role and put that
group's buckets on the inline policy (`oidc.group_roles`). A tight
`actions` list must include `s3:ListBucket`. Clients also send
`s3:GetBucketLocation` before that list, and `rgw_role_policy_present`
adds it when it is missing (`s3:*` already includes it). `aws s3 ls`
with no bucket is `s3:ListAllMyBuckets` on `arn:aws:s3:::*`, which these
policies do not grant. The S3 call has to use the temporary key, secret,
and session token from `AssumeRoleWithWebIdentity`, and the `RoleArn`
has to be a group role that has an inline policy. A trust-only role
(the formula's `oidc.role`, created only when `oidc.buckets` is set)
assumes cleanly and then 403s every bucket. The access log still shows
the OIDC shadow user (`$oidc$<sub>`), not the role name, so check
`AssumedRoleUser` in the STS response. The Keycloak access
token and the IAM admin key are not that session. An unsigned request
shows up in the RGW log as user `-`. There is no client secret on this
API. Thumbprints are SHA1 of the
IdP certs; STS compares them to the JWKS `x5c` entries, so a realm that
does not publish `x5c` will create cleanly and still fail
`AssumeRoleWithWebIdentity`.

The signing user needs `oidc-provider=*` caps **in the store's realm**.
The toolbox defaults to zone `default`, and a user created there will not
authenticate to the RGW serving the store. `oidc_provider_present` creates
`iam_user` with `radosgw-admin --rgw-realm/--rgw-zone` (defaulting those to
the store name) when `access_key` is omitted. Do not use
`CephObjectStoreUser` for this user: Rook's controller calls the Admin Ops
API and fails with `NoSuchBucket` on this store, so it never writes
`rook-ceph-object-user-*`.

```yaml
object_store_oidc_provider:
  rook.oidc_provider_present:
    - name: keycloak
    - namespace: rook-ceph
    - issuer_url: https://keycloak.example/realms/rsc
    - client_id: ss3-gateway
    - store: my-store
    - iam_user: rgw-iam-admin
    - endpoint: http://rook-ceph-rgw-my-store.rook-ceph.svc:80
    - thumbprints:
      - f7d7b3515dd0d319dd219a43a9ea727ad6065287
```

Omit `thumbprints` to discover them from the issuer JWKS (`x5c`), falling
back to the TLS leaf. Pass `access_key`/`secret_key` instead of `store` if
the Rook secret should not be used.

### RGW subuser (via the Ceph Mgr Dashboard API)

```yaml
glance_rgw_subuser:
  rook.rgw_subuser_present:
    - uid: glance
    - subuser: glance:swift
    - access: full
    - generate_secret: true
    - dashboard_endpoint: https://rook-ceph-mgr-dashboard.rook-ceph.svc:8443
    - dashboard_username: admin
    - dashboard_password: {{ pillar['osh']['ceph_dashboard_password'] }}
    - require:
      - rook: glance_rgw_user
```

**Prerequisite - one-time only, not automated by Rook:** the Ceph Mgr
Dashboard module must be told how to reach RGW before any `/api/rgw/*`
call will work:

```bash
ceph dashboard set-rgw-api-access-key -i <accesskeyfile>
ceph dashboard set-rgw-api-secret-key -i <secretkeyfile>
ceph dashboard set-rgw-api-host <rgw-service>
ceph dashboard set-rgw-api-port <port>
ceph dashboard set-rgw-api-scheme http
```

`dashboard_username`/`dashboard_password` just need to be a Dashboard user
with RGW management permissions - the built-in `admin` user Rook
provisions (see the `rook-ceph-dashboard-password` Secret) works fine.

## Pillar Examples

`resources_pillar` (for `ceph_cluster_present`):

```yaml
res-k8s:
  rook:
    resources:
      mon:
        limits:
          cpu: "2"
          memory: "2Gi"
        requests:
          cpu: "1"
          memory: "512Mi"
      osd:
        limits:
          cpu: "4"
          memory: "8Gi"
```

`placement_pillar` (for `ceph_cluster_present`) - a `node` key is
automatically remapped to `all`:

```yaml
res-k8s:
  rook:
    placement:
      node:
        tolerations:
          - key: node-role.kubernetes.io/rook-node
            operator: Exists
            effect: NoSchedule
```

## Notes

- All CR-based states (`ceph_cluster_present`, `ceph_blockpool_present`,
  `storageclass_present`, `ceph_object_store_present`,
  `ceph_object_store_user_present`) compare the *entire* live `spec`
  against the desired one for idempotency - any drift (including fields
  Rook itself defaults/normalizes) will trigger an update or
  delete-and-recreate cycle. Passing a full `spec` override where
  supported gives you more control over exactly what's compared.
- `storageclass_present` manages a cluster-scoped Kubernetes
  `StorageClass`, not a Rook/Ceph CRD - it's included here because it's
  typically defined alongside a `CephBlockPool` for RBD-backed dynamic
  provisioning.
- Requires the Python `kubernetes` client library on the minion (same
  dependency as `kinetic-k8s`); `rgw_subuser_present` additionally needs
  `requests` (already a transitive dependency in most Salt Python
  environments, no extra install needed).

Last updated: September 2026
