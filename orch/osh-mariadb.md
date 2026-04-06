# Outline of OpenStack Helm MariaDB Deployment with SaltStack

## Overview of `k8s-osh-mariadb.sls`

**Purpose**: This is an orchestration script designed to deploy OpenStack Helm MariaDB on a Kubernetes cluster. It uses SaltStack to target a specific minion (node) where the deployment should occur.

**Content**:
```/home/ubuntu/gcr/kinetic/orch/k8s-osh-mariadb.sls#L1-9
# Orchestration script to deploy OpenStack Helm MariaDB.
# This script uses the k8s pillar value to target the minion where the installation should occur.

{% set k8s = salt['pillar.get']('k8s') %}

deploy_osh_mariadb:
  salt.state:
    - tgt: {{ k8s }}
    - sls:
      - formulas.osh-mariadb
```

**Key Points**:
- The script retrieves the target minion from the `k8s` pillar value.
- It applies the Salt state `formulas.osh-mariadb` to the targeted minion.

## Overview of `configure.sls`

**Purpose**: This state file is part of the `osh-mariadb` formula and is responsible for installing and configuring the MariaDB Helm chart in the Kubernetes namespace `openstack`.

**Content**:
```/home/ubuntu/gcr/kinetic/formulas/osh-mariadb/configure.sls#L1-14
include:
  - /formulas/osh-mariadb/install
  - /formulas/osh-helm-repos/configure

install_mariadb:
  k8s_helm.helm_release_present:
    - release_name: mariadb
    - chart_name: openstack-helm/mariadb
    - namespace: openstack
    - wait_timeout: 300
    - wait_interval: 10
    - pillar_key: osh_values:mariadb
    - keep_values_file: True
```

**Key Points**:
- It includes other necessary state files for installation and Helm repository configuration.
- It uses the `k8s_helm.helm_release_present` module to ensure the MariaDB Helm chart is installed with specific parameters:
  - Release name: `mariadb`
  - Chart name: `openstack-helm/mariadb`
  - Namespace: `openstack`
  - Wait timeout and interval for deployment completion.
  - Configuration values are pulled from the pillar key `osh_values:mariadb`.

## How to Use This Orchestration Script and State File

1. **Prerequisites**:
   - Ensure that SaltStack is installed and configured on your system.
   - Verify that the Kubernetes cluster is accessible and the target minion is set in the `k8s` pillar.
   - Make sure the Helm chart repository for OpenStack is configured or accessible.

2. **Set Pillar Data**:
   - Update or set the `k8s` pillar value to point to the correct minion where the Kubernetes cluster is managed.
   - Configure the `osh_values:mariadb` pillar key with any specific values or overrides needed for the MariaDB deployment.

3. **Run the Orchestration Script**:
   - Execute the orchestration script using SaltStack with the `pepper` command as an example:
     ```bash
     pepper --client='runner' state.orchestrate orch.k8s-osh-mariadb pillar='{"k8s": "master-rsc-0"}'
     ```
   - This command will trigger the deployment on the specified minion, in this case, `master-rsc-0`.

4. **Monitor Deployment**:
   - Check the SaltStack logs or the Kubernetes cluster to ensure that the MariaDB Helm chart is deployed correctly in the `openstack` namespace.

5. **Troubleshooting**:
   - If the deployment fails, check the SaltStack execution output for errors.
   - Verify Helm chart availability and configuration in the Kubernetes cluster.
   - Ensure that the pillar data is correctly set and accessible by the Salt minion.
