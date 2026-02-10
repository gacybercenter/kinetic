## States

The following states are available under `_states/k8s.py`:

- **[k8s.bmh_present](#state-k8s.bmh_present)** - Ensures Bare Metal Host resources are present.
- **[k8s.networkdata_present](#state-k8s.networkdata_present)** - Ensures network data configurations are present.
- **[k8s.userdata_present](#state-k8s.userdata_present)** - Ensures userdata configurations are present for hosts.
- **[k8s.host_bmc_auth_present](#state-k8s.host_bmc_auth_present)** - Ensures BMC authentication is configured for hosts.
- **[k8s.uuids_present](#state-k8s.uuids_present)** - Ensures UUID secrets are present.
- **[k8s.mariadb_instance_present](#state-k8s.mariadb_instance_present)** - Ensures MariaDB instances are present in Kubernetes.
- **[k8s.local_storage_pv_pvc_present](#state-k8s.local_storage_pv_pvc_present)** - Ensures local storage PV and PVC are present.
- **[k8s.ironic_db_user_present](#state-k8s.ironic_db_user_present)** - Ensures database users for Ironic are present.
- **[k8s.mariadb_database_present](#state-k8s.mariadb_database_present)** - Ensures MariaDB databases are present.
- **[k8s.tls_secret_present](#state-k8s.tls_secret_present)** - Ensures TLS secrets are present for secure communication.
- **[k8s.ironic_operator_present](#state-k8s.ironic_operator_present)** - Ensures the Ironic operator is present.
- **[k8s.ironic_instance_present](#state-k8s.ironic_instance_present)** - Ensures Ironic instances are present for bare metal provisioning.
- **[k8s.image_server_present](#state-k8s.image_server_present)** - Ensures image servers are configured.
- **[k8s.bmh_state](#state-k8s.bmh_state)** - Manages the state of Bare Metal Hosts.
- **[k8s.namespace_present](#state-k8s.namespace_present)** - Ensures Kubernetes namespaces are present.
- **[k8s.ceph_cluster_present](#state-k8s.ceph_cluster_present)** - Ensures Ceph clusters are present for storage.
- **[k8s.configmap_present](#state-k8s.configmap_present)** - Ensures Kubernetes ConfigMaps are present.
- **[k8s.service_present](#state-k8s.service_present)** - Ensures Kubernetes Services are present.
- **[k8s.node_label_present](#state-k8s.node_label_present)** - Ensures labels are applied to Kubernetes nodes.
- **[k8s.metallb_pool_present](#state-k8s.metallb_pool_present)** - Ensures MetalLB IP address pools are configured.
- **[k8s.metallb_l2_advertisement_present](#state-k8s.metallb_l2_advertisement_present)** - Ensures MetalLB L2 advertisements are present.
- **[k8s.certmanager_issuer_present](#state-k8s.certmanager_issuer_present)** - Ensures Cert-Manager issuers are present for certificate management.
- **[k8s.ingress_present](#state-k8s.ingress_present)** - Ensures Kubernetes Ingress resources are present.
- **[k8s.certmanager_certificate_present](#state-k8s.certmanager_certificate_present)** - Ensures certificates are managed via Cert-Manager.
- **[k8s.cnpg_cluster_present](#state-k8s.cnpg_cluster_present)** - Ensures CloudNativePG clusters are present for PostgreSQL.
- **[k8s.secret_present](#state-k8s.secret_present)** - Ensures Kubernetes Secrets are present.
- **[k8s.keycloak_cluster_present](#state-k8s.keycloak_cluster_present)** - Ensures Keycloak clusters are present for identity and access management.
- **[k8s.certificate_present](#state-k8s.certificate_present)** - Ensures certificates are directly managed.
- **[k8s.pvc_present](#state-k8s.pvc_present)** - Ensures Persistent Volume Claims are present in Kubernetes.
