# Swift / Rook Gateway Formula

This formula deploys OpenStack Swift object storage using Rook's Ceph RGW (`CephObjectStore`).

## What it does

- Creates the `keystone-admin` Kubernetes Secret in the `rook-ceph` namespace. This secret contains the OpenStack credentials that the RGW gateway itself uses to authenticate against Keystone.
- Deploys a `CephObjectStore` named `rsc-object-store` via the `rook.ceph_object_store_present` state.
- Configures RGW with:
  - S3 + Swift frontends (`enable_apis`)
  - Keystone authentication integration
  - Custom `rgwConfig` settings (timeouts, thread pool, object sizes, etc.)
  - Custom `rgwCommandFlags` (e.g. Beast frontend settings)
- Creates a `HTTPRoute` that exposes the RGW service through the external `traefik-external` Gateway.
- Registers the Swift service and its three endpoints (admin, internal, public) in the Keystone service catalog using the `kinetic_openstack` states.

  Unlike most other OpenStack-Helm services (where the Helm chart itself registers the service and endpoints in Keystone), the Rook `CephObjectStore` CRD does **not** perform this registration. The Swift formula therefore explicitly creates the service catalog entries as a separate step.

## Key Files

| File | Purpose |
|------|---------|
| `install.sls` | (Currently empty) Placeholder for any future package or dependency setup |
| `configure.sls` | Main logic: secrets, CephObjectStore CR, HTTPRoute, Keystone catalog entries |

## Important Notes

- TLS certificates for Swift are **not** managed by this formula. The HTTPRoute assumes the certificate is already attached to the `websecure-ext` listener on the external Gateway.
- The `keystone-admin` secret **must** exist before the `CephObjectStore` is created when `auth_keystone: true` is used.
- Changing certain `rgw_config` keys or `enable_apis` will cause the state to delete and recreate the `CephObjectStore`. When `preserve_pools_on_delete: true`, you must manually remove the finalizer on the CR before the recreation can complete. See the [CRD recreation / finalizer workaround](../docs/kinetic-swift.md#crd-recreation--finalizer-workaround) section in the module documentation for the required steps.

### Load Balancer Transport Settings (`res-k8s:lbs`)

To support streaming large objects between the external Gateway and the Swift service, the following transport timeout settings are configured under the `res-k8s:lbs` pillar:

```yaml
transport:
  respondingTimeouts:
    readTimeout: 30m
    writeTimeout: 30m
    idleTimeout: 300s
```

These extended timeouts prevent the Gateway from prematurely closing connections during large uploads or downloads.

## Usage

Apply via the normal orchestration or state run:

```bash
salt '<target>' state.apply formulas.swift
```

Or include it from a higher-level orchestration that also manages Rook and Keystone.