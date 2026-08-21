# Salt State File for Ironic Standalone Operator Setup

## Include External Formulas (include)

### Purpose
Incorporates shared Salt formulas or states for Kubernetes and MariaDB setup.

### Details
Includes `k8s-mariadb`, which likely provides common configurations or dependencies for Kubernetes and MariaDB Operator setups used across multiple services.

### Role
Ensures reusable configurations are available for managing Kubernetes resources and MariaDB instances.

## Install Dependencies (ironic_dependancies)

### Purpose
Installs required system packages for the Ironic Operator setup.

### Details
Installs `podman`, a container runtime likely needed for building or running containers as part of the Ironic Operator deployment.

### Role
Prepares the host system with necessary tools before proceeding with further configuration or deployment steps.

## Create Directory for Ironic Operator (create_ironic_op_dir)

### Purpose
Sets up a directory to store the Ironic Operator source code or related files.

### Details
Creates a directory at the path specified by `{{ pillar['ironic_op_dir'] }}` with root ownership and permissions 755 for directories and 644 for files.

### Role
Provides a dedicated location for cloning and managing the Ironic Operator repository.

## Create Directory for Ironic Database Storage (create_ironic_db_dir)

### Purpose
Sets up a directory for storing MariaDB data for the Ironic database.

### Details
Creates a directory at `{{ pillar['ironic_db_dir'] }}` with ownership set to UID/GID 999 (likely corresponding to the mysql user in the MariaDB container) and permissions 755/644.

### Role
Ensures a local storage path exists on the host for persistent data used by the MariaDB instance.

## Ensure Kubernetes Storage Resources (ensure_k8s_storage)

### Purpose
Manages Kubernetes Persistent Volume (PV) and Persistent Volume Claim (PVC) for local storage.

### Details
Uses the custom state `k8s.local_storage_pv_pvc_present` to create a PV and PVC named based on `{{ pillar['ironic_db_dir'] }}` with a size of 5Gi, tied to the local path `{{ pillar['ironic_db_dir'] }}`, and using the `local-storage` storage class in the namespace `{{ pillar['bmo_namespace'] }}`.

### Dependencies
Requires `create_ironic_db_dir` to ensure the local directory exists before creating the PV.

### Role
Provides persistent storage for the MariaDB instance by linking a local directory to Kubernetes storage resources.

## Ensure MariaDB Instance (ensure_mariadb_instance)

### Purpose
Deploys a MariaDB instance in Kubernetes for use by Ironic.

### Details
Uses the custom state `k8s.mariadb_instance_present` to create or update a MariaDB instance named `ironic-mariadb` in the namespace `{{ pillar['bmo_namespace'] }}`. Configures it with a specified root password, image (`mariadb:10.6`), storage settings (size 5Gi, class `local-storage`), resource limits/requests, and grants access to root from IP `192.168.1.41`.

### Dependencies
Requires `ensure_k8s_storage` to ensure storage resources are ready.

### Role
Sets up the database server required for Ironic to store its data.

## Ensure Ironic Database (ensure_ironic_database)

### Purpose
Creates a specific database named `ironic` within the MariaDB instance.

### Details
Uses the custom state `k8s.mariadb_database_present` to create or update a Database resource named `ironic` in the namespace `{{ pillar['bmo_namespace'] }}`, linked to the `ironic-mariadb` instance, with character set `utf8` and collation `utf8_general_ci`.

### Dependencies
Requires `ensure_mariadb_instance` to ensure the MariaDB server is deployed.

### Role
Ensures the specific database for Ironic exists within the MariaDB instance.

## Ensure Ironic Database User (ensure_ironic_db_user)

### Purpose
Configures a database user with appropriate permissions for Ironic.

### Details
Uses the custom state `k8s.ironic_db_user_present` to create or update a user with a name and password from pillar data, stored in a Secret named `ironic-user`, with full privileges on the `ironic` database, allowing access from any host (`%`).

### Dependencies
Requires `ensure_mariadb_instance` to ensure the database server is ready.

### Role
Provides secure access credentials for Ironic to interact with its database.

## Configure Git Safe Directory (git_ironic_repo)

### Purpose
Configures Git to trust the directory where the Ironic Operator repository will be cloned.

### Details
Sets the Git configuration `safe.directory` to `{{ pillar['ironic_op_dir'] }}` globally, ensuring Git operations in this directory are allowed without security warnings.

### Role
Prepares the system to safely clone and work with the Ironic Operator repository.

## Clone Ironic Operator Repository (clone_ironic_repo)

### Purpose
Downloads the Ironic Standalone Operator source code from GitHub.

### Details
Clones the repository `https://github.com/metal3-io/ironic-standalone-operator` to `{{ pillar['ironic_op_dir'] }}`, checking out the branch or release specified by `{{ pillar['ironic_op_release'] }}`.

### Dependencies
Requires `create_ironic_op_dir` and `git_ironic_repo` to ensure the directory exists and Git is configured.

### Role
Retrieves the necessary code for deploying the Ironic Operator.

## Install and Deploy Ironic Operator (install_deploy_ironic_operator)

### Purpose
Builds and deploys the Ironic Standalone Operator to the Kubernetes cluster.

### Details
Runs `make install deploy` in the cloned repository directory (`{{ pillar['ironic_op_dir'] }}`) to install Custom Resource Definitions (CRDs) and deploy the operator.

### Conditional Execution
Uses `onchanges` to run only if `clone_ironic_repo` reports changes (e.g., repository was cloned or updated).

### Dependencies
Requires `ironic_dependancies` to ensure necessary tools like `podman` are installed.

### Role
Deploys the Ironic Operator to manage bare metal resources in the cluster.

## Wait for Ironic Operator Deployment (wait_for_ironic_deployment)

### Purpose
Ensures the Ironic Operator deployment is ready before proceeding.

### Details
Runs `kubectl wait` to block until the `ironic-standalone-operator-controller-manager` deployment in the `ironic-standalone-operator-system` namespace reaches the `Available` condition, with a timeout of 60 seconds.

### Dependencies
Requires `install_deploy_ironic_operator` to ensure the deployment command has been executed.

### Role
Guarantees that the Ironic Operator is fully operational before any subsequent states or operations depend on it.

## Overall Purpose of the State File

### Objective
This Salt state file automates the setup and deployment of the Ironic Standalone Operator in a Kubernetes environment, including all necessary dependencies, database infrastructure, and operator deployment.

### Workflow
It progresses from setting up basic system requirements (directories and packages), to configuring persistent storage, deploying a MariaDB instance with a specific database and user for Ironic, and finally cloning, installing, and verifying the deployment of the Ironic Operator.

### Dependencies and Order
The states are ordered with `require` and `onchanges` requisites to ensure proper sequencing (e.g., storage before database, database before user, repository clone before deployment) and to avoid unnecessary re-execution of steps like deployment if the repository hasn't changed.