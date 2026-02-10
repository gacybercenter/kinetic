# Kinetic Kubernetes SaltStack Modules and States

This repository contains custom SaltStack modules and states for managing Kubernetes resources and related configurations. Below you will find detailed lists of the available modules and states, formatted similarly to the official SaltStack documentation.

## Modules

The following modules are available under `_modules/kinetic-k8s.py`:

- **[kinetic_k8s.bmh_present](#module-kinetic_k8s.bmh_present)** - Manages Bare Metal Host (BMH) resources.
- **[kinetic_k8s.networkdata_present](#module-kinetic_k8s.networkdata_present)** - Handles network data configuration for hosts.
- **[kinetic_k8s.userdata_present](#module-kinetic_k8s.userdata_present)** - Manages userdata configuration for hosts.
- **[kinetic_k8s.host_bmc_auth_present](#module-kinetic_k8s.host_bmc_auth_present)** - Configures BMC authentication for hosts.
- **[kinetic_k8s.uuids_secret_present](#module-kinetic_k8s.uuids_secret_present)** - Manages UUID secrets.
- **[kinetic_k8s.mariadb_instance_present](#module-kinetic_k8s.mariadb_instance_present)** - Manages MariaDB instances in a Kubernetes environment.
- **[kinetic_k8s.local_storage_pv_pvc_present](#module-kinetic_k8s.local_storage_pv_pvc_present)** - Configures local storage Persistent Volumes (PV) and Persistent Volume Claims (PVC).
- **[kinetic_k8s.ironic_db_user_setup](#module-kinetic_k8s.ironic_db_user_setup)** - Sets up database users for Ironic.
- **[kinetic_k8s.mariadb_database_present](#module-kinetic_k8s.mariadb_database_present)** - Manages MariaDB databases.
- **[kinetic_k8s.generate_tls_secret](#module-kinetic_k8s.generate_tls_secret)** - Generates TLS secrets for secure communication.
- **[kinetic_k8s.check_ironic_operator](#module-kinetic_k8s.check_ironic_operator)** - Checks the status of the Ironic operator.
- **[kinetic_k8s.ironic_instance_present](#module-kinetic_k8s.ironic_instance_present)** - Manages Ironic instances for bare metal provisioning.
- **[kinetic_k8s.image_server_present](#module-kinetic_k8s.image_server_present)** - Configures image servers for use in deployments.
- **[kinetic_k8s.bmh_state](#module-kinetic_k8s.bmh_state)** - Retrieves or sets the state of Bare Metal Hosts.
- **[kinetic_k8s.namespace_present](#module-kinetic_k8s.namespace_present)** - Manages Kubernetes namespaces.
- **[kinetic_k8s.ceph_cluster_present](#module-kinetic_k8s.ceph_cluster_present)** - Configures Ceph clusters for storage.
- **[kinetic_k8s.configmap_present](#module-kinetic_k8s.configmap_present)** - Manages Kubernetes ConfigMaps.
- **[kinetic_k8s.service_present](#module-kinetic_k8s.service_present)** - Manages Kubernetes Services.
- **[kinetic_k8s.node_label_present](#module-kinetic_k8s.node_label_present)** - Applies labels to Kubernetes nodes.
- **[kinetic_k8s.metallb_pool_present](#module-kinetic_k8s.metallb_pool_present)** - Configures MetalLB IP address pools.
- **[kinetic_k8s.metallb_l2_advertisement_present](#module-kinetic_k8s.metallb_l2_advertisement_present)** - Manages MetalLB L2 advertisements.
- **[kinetic_k8s.certmanager_issuer_present](#module-kinetic_k8s.certmanager_issuer_present)** - Configures Cert-Manager issuers for certificate management.
- **[kinetic_k8s.ingress_present](#module-kinetic_k8s.ingress_present)** - Manages Kubernetes Ingress resources.
- **[kinetic_k8s.certmanager_certificate_present](#module-kinetic_k8s.certmanager_certificate_present)** - Manages certificates via Cert-Manager.
- **[kinetic_k8s.cnpg_cluster_present](#module-kinetic_k8s.cnpg_cluster_present)** - Configures CloudNativePG clusters for PostgreSQL.
- **[kinetic_k8s.secret_present](#module-kinetic_k8s.secret_present)** - Manages Kubernetes Secrets.
- **[kinetic_k8s.keycloak_cluster_present](#module-kinetic_k8s.keycloak_cluster_present)** - Configures Keycloak clusters for identity and access management.
- **[kinetic_k8s.certificate_present](#module-kinetic_k8s.certificate_present)** - Manages certificates directly.
- **[kinetic_k8s.pvc_present](#module-kinetic_k8s.pvc_present)** - Manages Persistent Volume Claims (PVC) in Kubernetes.
