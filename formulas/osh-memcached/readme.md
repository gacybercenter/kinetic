## Overview of `k8s-osh-memcached.sls`

**Purpose**: This is an orchestration script designed to deploy OpenStack Helm Memcached on a Kubernetes cluster. It uses SaltStack to target a specific minion (node) where the deployment should occur.

**Content**:
```/home/ubuntu/gcr/kinetic/orch/k8s-osh-memcached.sls#L1-9
# Orchestration script to deploy OpenStack Helm Memcached.
# This script uses the k8s pillar value to target the minion where the installation should occur.

{% set k8s = salt['pillar.get']('k8s') %}

deploy_osh_memcached:
  salt.state:
    - tgt: {{ k8s }}
    - sls:
      - formulas.osh-memcached
```

**Key Points**:
- The script retrieves the target minion from the `k8s` pillar value.
- It applies the Salt state `formulas.osh-memcached` to the targeted minion.

## Overview of `configure.sls`

**Purpose**: This state file is part of the `osh-memcached` formula and is responsible for installing and configuring the Memcached Helm chart in the Kubernetes namespace `openstack`.

**Content**:
```/home/ubuntu/gcr/kinetic/formulas/osh-memcached/configure.sls#L1-14
include:
  - /formulas/osh-memcached/install
  - /formulas/osh-helm-repos/configure

install_memcached:
  k8s_helm.helm_release_present:
    - release_name: memcached
    - chart_name: openstack-helm/memcached
    - namespace: openstack
    - wait_timeout: 300
    - wait_interval: 10
    - keep_values_file: true
    - pillar_key: osh_values:memcached
```

**Key Points**:
- It includes other necessary state files for installation and Helm repository configuration.
- It uses the `k8s_helm.helm_release_present` module to ensure the Memcached Helm chart is installed with specific parameters:
  - Release name: `memcached`
  - Chart name: `openstack-helm/memcached`
  - Namespace: `openstack`
  - Wait timeout and interval for deployment completion.
  - Configuration values are pulled from the pillar key `osh_values:memcached`.

## How to Use This Orchestration Script and State File

1. **Prerequisites**:
   - Ensure that SaltStack is installed and configured on your system.
   - Verify that the Kubernetes cluster is accessible and the target minion is set in the `k8s` pillar.
   - Make sure the Helm chart repository for OpenStack is configured or accessible.

2. **Set Pillar Data**:
   - Update or set the `k8s` pillar value to point to the correct minion where the Kubernetes cluster is managed.
   - Configure the `osh_values:memcached` pillar key with any specific values or overrides needed for the Memcached deployment.

3. **Run the Orchestration Script**:
   - Execute the orchestration script using SaltStack with the `pepper` command as an example:
     ```bash
     pepper --client='runner' state.orchestrate orch.k8s-osh-memcached pillar='{"k8s": "master-rsc-0"}'
     ```
   - This command will trigger the deployment on the specified minion, in this case, `master-rsc-0`.

4. **Monitor Deployment**:
   - Check the SaltStack logs or the Kubernetes cluster to ensure that the Memcached Helm chart is deployed correctly in the `openstack` namespace.

5. **Troubleshooting**:
   - If the deployment fails, check the SaltStack execution output for errors.
   - Verify Helm chart availability and configuration in the Kubernetes cluster.
   - Ensure that the pillar data is correctly set and accessible by the Salt minion.
