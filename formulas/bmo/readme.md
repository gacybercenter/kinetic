# Bare Metal Operator (BMO) and Ironic Installation State Documentation

## Overview
The `install.sls` file, located at `/home/ubuntu/gcr/kinetic/formulas/bmo/install.sls`, is a SaltStack state file responsible for setting up the Bare Metal Operator (BMO) and Ironic components within the Kinetic project. These components are crucial for managing bare metal infrastructure, likely as part of an OpenStack deployment. The state handles dependency installation, configuration, credential management, and deployment using Kubernetes tools like `kubectl` and `kustomize`.

## Purpose
This state automates the installation and configuration of BMO and Ironic, ensuring that:
- Necessary dependencies (e.g., `kubectl`, `kustomize`) are installed.
- Required directories and temporary overlays are created.
- Authentication credentials are generated and managed (if basic auth is enabled).
- Kubernetes resources are deployed using `kustomize` for both BMO and Ironic, with conditional configurations for TLS, basic authentication, and MariaDB integration.
- Temporary files are cleaned up post-deployment.

## Prerequisites
- **SaltStack**: The environment must have SaltStack installed and configured to apply states.
- **Kubernetes**: A working Kubernetes cluster with `kubectl` access is assumed for deploying resources.
- **Pillar Data**: The state relies heavily on pillar variables (e.g., `deploy_bmo`, `deploy_ironic`, `deploy_tls`, `bmo_namespace`, etc.) to customize the deployment.

## State Breakdown

### 1. Validation of Deployment Options
- **Purpose**: Ensures that at least one of BMO or Ironic is set to deploy, and if MariaDB is deployed, TLS must be enabled.
- **States**:
  - `validate_deployment`: Fails if neither `deploy_bmo` nor `deploy_ironic` is `True`.
  - `validate_deployment` (second check): Fails if `deploy_mariadb` is `True` but `deploy_tls` is `False`.

### 2. Dependency Installation
- **Purpose**: Installs required tools for Kubernetes operations.
- **States**:
  - `install_dependencies` (pkg): Installs `kubectl` and `curl`.
  - `install_dependencies` (cmd): Downloads and installs `kustomize` version 5.4.1 if not already present.

### 3. Directory Setup
- **Purpose**: Creates necessary directories for Ironic data, authentication, and temporary overlays.
- **States**:
  - `ironic_directories`: Creates directories for Ironic data and auth with mode 755.
  - `temp_overlay_dirs`: Creates temporary overlay directories for BMO and Ironic, cleaning existing contents if necessary.

### 4. Credential Management (Conditional on `deploy_basic_auth`)
- **Purpose**: Generates and manages credentials for Ironic if basic authentication is enabled.
- **States**:
  - `ironic_credentials_username` & `ironic_credentials_password`: Creates files with username and password (defaulting to UUID if not specified) in the auth directory.
  - `bmo_credentials_username` & `bmo_credentials_password`: Copies credentials to the BMO overlay directory.
  - `ironic_htpasswd`: Generates an `htpasswd` file for Ironic using the provided credentials.

### 5. Namespace Creation
- **Purpose**: Sets up the Kubernetes namespace for BMO and Ironic.
- **States**:
  - `bmo_ironic_namespace`: Creates the namespace specified in `bmo_namespace` if it doesn't exist.

### 6. BMO Deployment (Conditional on `deploy_bmo`)
- **Purpose**: Configures and deploys the Bare Metal Operator using `kustomize`.
- **States**:
  - `bmo_kustomize_overlay`: Creates a `kustomization.yaml` file for BMO, including resources, namespace, and conditional components for basic auth and TLS.
  - `bmo_ironic_env`: Manages the `ironic.env` configuration file for BMO.
  - `bmo_deploy`: Builds and applies the BMO configuration using `kustomize` and `kubectl` if the BMO controller manager is not already deployed.

### 7. Ironic Deployment (Conditional on `deploy_ironic`)
- **Purpose**: Configures and deploys Ironic using `kustomize`.
- **States**:
  - `ironic_kustomize_overlay`: Creates a `kustomization.yaml` file for Ironic, with conditional resources and components based on basic auth, TLS, and MariaDB settings.
  - `ironic_bmo_configmap`: Manages the `ironic_bmo_configmap.env` file, setting environment variables like `IRONIC_EXTERNAL_IP`.
  - `update_tls_certificate` (Conditional on `deploy_tls`): Updates the TLS certificate YAML with the Ironic host IP.
  - `update_mariadb_certificate` (Conditional on `deploy_mariadb`): Updates the MariaDB certificate YAML with the MariaDB host IP.
  - `ironic_deploy`: Builds and applies the Ironic configuration using `kustomize` and `kubectl` if Ironic is not already deployed.

### 8. Cleanup (Conditional on `deploy_basic_auth`)
- **Purpose**: Removes temporary credential files after deployment to maintain security.
- **States**:
  - `cleanup_bmo_credentials`: Deletes temporary BMO credential files post-deployment.
  - `cleanup_ironic_credentials`: Deletes temporary Ironic `htpasswd` file post-deployment.

## Key Pillar Variables
- `deploy_bmo`: Boolean to determine if BMO should be deployed.
- `deploy_ironic`: Boolean to determine if Ironic should be deployed.
- `deploy_basic_auth`: Boolean to enable basic authentication setup.
- `deploy_tls`: Boolean to enable TLS configurations.
- `deploy_mariadb`: Boolean to enable MariaDB integration.
- `bmo_namespace`: Kubernetes namespace for BMO and Ironic.
- `ironic_data_dir`, `ironic_auth_dir`: Directories for Ironic data and authentication.
- `temp_bmo_overlay`, `temp_ironic_overlay`: Temporary directories for overlay configurations.
- `ironic_username`, `ironic_password`: Credentials for Ironic (defaults to UUID if not set).
- `ironic_endpoint_ip`: IP address for Ironic external access.
- `mariadb_host_ip`: IP address for MariaDB host.
- `script_dir`: Directory containing configuration scripts and resources.

## Usage
This state is intended to be applied via SaltStack as part of a larger orchestration workflow for setting up bare metal provisioning infrastructure. It can be executed with:
```shell
salt 'target_minion' state.apply bmo.install

## Remove/Reinstall

### Reinstall
To reinstall a node, follow these steps:
1. Delete the BareMetalHost (BMH) associated with the node. This will remove the node from the cluster. Use the following command, replacing `<node name>` with the name of your node:
   ```shell
   kubectl -n baremetal-operator-system delete bmh baremetal-operator~<node name>
2. Wait for the node to restart and boot into the clean process. Once the cleaning process is finished, the node will power down.
3. To install again, run the following command to re-apply the configuration:
  ```shell
  salt 'bmo' state.apply formulas.bmo.configure
