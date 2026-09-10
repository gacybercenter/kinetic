# Glance Formula

This formula deploys the OpenStack Glance image service using the OpenStack-Helm chart, with external access provided via an HTTPRoute through the Gateway.

## What it does

- Normalizes the list of hostnames for Glance from pillar (`osh:glance:glance_ingress:hosts`).
- Creates a `k8s.httproute_present` that routes external Glance API traffic through the `traefik-external` Gateway (`websecure-ext` listener) to the `glance-api` service on port 9292.
- Deploys Glance via the `k8s_helm.helm_release_present` state using the `openstack-helm/glance` chart.
- Passes endpoint passwords and credentials for:
  - MariaDB (Glance database user)
  - RabbitMQ (messaging)
  - Keystone (identity)
  - Ceph Object Store (Glance Swift backend password)

TLS termination is handled at the Gateway listener; the certificate is managed elsewhere.

## Key Files

| File          | Purpose                                      |
|---------------|----------------------------------------------|
| `install.sls` | (Currently empty) Placeholder for dependencies |
| `configure.sls` | Main logic: HTTPRoute + Helm release deployment |

## Important Notes

- Unlike Swift (which uses a Rook `CephObjectStore` CR), Glance is deployed via the standard OpenStack-Helm Helm chart.
- The Helm chart itself typically handles Keystone service catalog registration for Glance. The formula does not explicitly create `kinetic_openstack.service_present` or endpoint states.
- The HTTPRoute assumes the external Gateway and its TLS listener already exist.
- Passwords are pulled from multiple pillar locations (`osh:glance:values`, `osh:osh_users`, etc.). Ensure these are populated before running the formula.

### Pillar Configuration Notes

- `helm:storage` is set to `rbd` (instead of `swift`) because RBD-backed storage performs faster than Swift in this environment.
- Custom `uwsgi` settings under `conf:glance_api_uwsgi` are required to properly handle streaming between the external Gateway and the Glance API service. These settings will be documented in more detail later.
- Endpoint ports (under `endpoints`) must be explicitly defined even though the chart documentation claims they have defaults. The Helm templates can otherwise emit partially-parsed JSON values that cause Helm to fail during rendering.

## Usage

Apply via the normal state or orchestration run:

```bash
salt '<target>' state.apply formulas.glance
```

