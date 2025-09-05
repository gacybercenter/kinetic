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
efk_namespace: efk
opensearch_version: 3.2.0
opensearch_replicas: 3
opensearch_cluster_name: opensearch-cluster
opensearch_admin_password: |
  <PGP>
opensearch_admin_hash: |
  <PGP>
opensearch_fluentbit_hash: |
  <PGP>
opensearch_dashboard_user_hash:
  <PGP>
opensearch_cpu_limit: 2000m
opensearch_memory_limit: 1024Mi
opensearch_cpu_request: 1000m
opensearch_memory_request: 512Mi
opensearch_persistence_enabled: true
opensearch_persistence_size: 10Gi
opensearch_service_type: ClusterIP
opensearch_service_host: opensearch-cluster-master
opensearch_service_port: 9200
opensearch_tls_enabled: On
opensearch_tls_verify: Off
opensearch_suppress_type_name: On
fluent_bit_version: 0.47.0
opensearch_fluentbit_username: fluentbit
opensearch_fluentbit_password: | 
  <PGP>
fluent_bit_memory_request: 100Mi
fluent_bit_cpu_request: 100m
fluent_bit_memory_limit: 200Mi
fluent_bit_cpu_limit: 200m

fluentd_password: | 
  <PGP>
opensearch_security_secrets:
  internal_users: internal-users-secret
  roles: roles-secret
  roles_mapping: roles-mapping-secret
  action_groups: action-groups-secret
  config: config-secret
  tenants: tenants-secret
```

## To run the orchestration script

```bash
pepper --client='runner' state.orchestrate orch.k8s-efk pillar='{"k8s": "master-rsc-0"}'
```
