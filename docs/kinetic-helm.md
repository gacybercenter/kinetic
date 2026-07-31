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



### OCI chart (new)
```yaml
myapp:
  k8s_helm.helm_release_present:
    - release_name: myapp
    - chart_name: oci://ghcr.io/myorg/myapp-chart
    - namespace: default
    - version: 1.2.3
    - pillar_key: helm:myapp:values

```yaml
### OCI chart with explicit values and multiple value files
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


## State Module

Use the  state module for declarative orchestration:


```yaml
ensure_helm_release:
  k8s_helm.helm_release_present:
    - release_name: my-release
    - chart_name: oci://ghcr.io/org/chart
    - namespace: default
    - pillar_key: helm:values


## Notes

- OCI charts do not require a  step
- Private OCI registries may require prior 
- The module uses  for all cases

Last updated: July 2025
