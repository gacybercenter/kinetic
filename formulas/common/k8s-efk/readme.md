# Kubernetes EFK Stack Deployment with SaltStack

This formula provides Salt states for deploying the EFK (Elasticsearch, Fluentd, Kibana) stack on a Kubernetes cluster using Helm. Currently, it focuses on installing Elasticsearch as the foundation of the logging stack.

## Overview

The `k8s-efk` formula includes the following components:

- **Namespace Management**: Creates a dedicated namespace for the EFK stack (default: `efk`).
- **Helm Repository Management**: Adds and manages the Elastic Helm repository.
- **Elasticsearch Installation**: Deploys Elasticsearch using the Helm chart from the Elastic repository with customizable values.

### Files Structure

- `init.sls`: Entry point that includes the configuration state.
- `configure.sls`: Includes the installation state.
- `install.sls`: Defines the states for creating the namespace, managing the Helm repository, rendering configuration values, and installing Elasticsearch.
- `files/elasticsearch-values.j2`: Jinja2 template for customizing Elasticsearch Helm chart values.
- `orch/k8s-efk.sls`: Orchestration state to apply the EFK installation on a targeted Kubernetes node.

## Prerequisites

- SaltStack master and minion setup.
- Kubernetes cluster accessible from the targeted minion with `kubectl` installed.
- Helm installed on the minion where the states will be applied.
- Pillar data configured with necessary values (e.g., `k8s` target, `efk_namespace`, `elasticsearch_version`, etc.).

## Pillar Data Configuration

Customize the deployment using pillar data. Below is an example of pillar data structure:

```yaml
elasticsearch_version: 8.5.1
efk_namespace: efk
elasticsearch_values:
  replicas: 3
  minimumMasterNodes: 2
  clusterName: "elastic-cluster"
  nodeGroup: "master"
  roles:
    master: "true"
    data: "true"
    ingest: "true"
  resources:
    limits:
      cpu: "1000m"
      memory: "1024Mi"
    requests:
      cpu: "500m"
      memory: "512Mi"
  persistence:
    enabled: true
    size: "10Gi"
  service:
    type: ClusterIP
```

## To run the orchestration script

```bash
pepper --client='runner' state.orchestrate orch.k8s-efk pillar='{"k8s": "master-rsc-0"}'
```
