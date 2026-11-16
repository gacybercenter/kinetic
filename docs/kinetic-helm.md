# kinetic-helm Module

SaltStack execution and state modules for managing Helm repositories and releases in Kubernetes.

## Features

- Add or update Helm repositories
- Install or upgrade Helm releases with values from pillar or direct dict
- Support for `--set` and additional `--values` files
- **OCI chart support**: Install charts directly from OCI registries (e.g., GHCR, ACR) without adding a repository

## Usage Examples

### Traditional repository chart

```yaml
my-nginx:
  k8s_helm.helm_release_present:
    - release_name: my-nginx
    - chart_name: bitnami/nginx
    - namespace: default
    - pillar_key: helm:nginx:values
    - version: 15.0.0
```

`pillar_key` is resolved with `pillar.get(pillar_key, {})`, so Salt's
colon-delimited nested-key lookup applies - `helm:nginx:values` reads
`pillar['helm']['nginx']['values']`, and that entire dict is passed to Helm
as the chart's values (equivalent to a `values.yaml`). For the example
above, a matching pillar entry would look like:

```yaml
helm:
  nginx:
    values:
      replicaCount: 2
      image:
        registry: docker.io
        repository: bitnami/nginx
        tag: 1.27.0
      service:
        type: ClusterIP
        ports:
          http: 80
      ingress:
        enabled: false
      resources:
        limits:
          cpu: "500m"
          memory: "256Mi"
        requests:
          cpu: "100m"
          memory: "128Mi"
```

The exact keys available depend on the chart/version being installed (the
sample above matches the Bitnami nginx chart's common options) - check the
chart's own `values.yaml`/README for the authoritative schema.

### OCI chart

```yaml
myapp:
  k8s_helm.helm_release_present:
    - release_name: myapp
    - chart_name: oci://ghcr.io/myorg/myapp-chart
    - namespace: default
    - version: 1.2.3
    - pillar_key: helm:myapp:values
```

### OCI chart with explicit values and multiple value files

```yaml
myapp:
  k8s_helm.helm_release_present:
    - release_name: myapp
    - chart_name: oci://registry.example.com/charts/app
    - namespace: default
    - values_dict:
        replicaCount: 3
        image:
          tag: v2.0.0
    - set_values:
        - ingress.enabled=true
    - values_files:
        - /path/to/base-values.yaml
        - /path/to/env-values.yaml
```

## State Module

Use the `k8s_helm` state module for declarative orchestration:

```yaml
ensure_helm_release:
  k8s_helm.helm_release_present:
    - release_name: my-release
    - chart_name: oci://ghcr.io/org/chart
    - namespace: default
    - pillar_key: helm:values
```

## Notes

- OCI charts do not require a `helm repo add` step
- Private OCI registries may require prior `helm registry login`
- The module uses `helm upgrade --install` for all cases

Last updated: July 2025
