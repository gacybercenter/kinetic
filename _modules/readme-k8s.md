# Kinetic Kubernetes SaltStack Modules and States

This repository contains custom SaltStack modules and states for managing Kubernetes resources and related configurations. Below you will find detailed lists of the available modules and states, formatted similarly to the official SaltStack documentation.

## Modules

The following modules are available under `_modules/kinetic-k8s.py`:

- **[kinetic_k8s.bmh_present](#module-kinetic_k8s.bmh_present)** - Manages Bare Metal Host (BMH) resources.
  - **Example**: `salt '*' kinetic_k8s.bmh_present name='host1' namespace='openstack' bmc_address='ipmi://192.168.1.10'`
- **[kinetic_k8s.networkdata_present](#module-kinetic_k8s.networkdata_present)** - Handles network data configuration for hosts.
  - **Example**: `salt '*' kinetic_k8s.networkdata_present name='host1-net' namespace='openstack' interfaces='[{"name": "eth0", "ip": "192.168.1.20"}]'`
- **[kinetic_k8s.userdata_present](#module-kinetic_k8s.userdata_present)** - Manages userdata configuration for hosts.
  - **Example**: `salt '*' kinetic_k8s.userdata_present name='host1-userdata' namespace='openstack' userdata='#!/bin/bash\necho "Setup host"'`
- **[kinetic_k8s.host_bmc_auth_present](#module-kinetic_k8s.host_bmc_auth_present)** - Configures BMC authentication for hosts.
  - **Example**: `salt '*' kinetic_k8s.host_bmc_auth_present name='host1-bmc' namespace='openstack' username='admin' password='secret'`
- **[kinetic_k8s.uuids_secret_present](#module-kinetic_k8s.uuids_secret_present)** - Manages UUID secrets.
  - **Example**: `salt '*' kinetic_k8s.uuids_secret_present name='uuids-secret' namespace='openstack' uuids='{"host1": "uuid-1234"}'`
- **[kinetic_k8s.mariadb_instance_present](#module-kinetic_k8s.mariadb_instance_present)** - Manages MariaDB instances in a Kubernetes environment.
  - **Example**: `salt '*' kinetic_k8s.mariadb_instance_present name='mariadb1' namespace='openstack' replicas=1 storage_size='10Gi'`
- **[kinetic_k8s.local_storage_pv_pvc_present](#module-kinetic_k8s.local_storage_pv_pvc_present)** - Configures local storage Persistent Volumes (PV) and Persistent Volume Claims (PVC).
  - **Example**: `salt '*' kinetic_k8s.local_storage_pv_pvc_present name='local-storage' namespace='openstack' size='5Gi' path='/mnt/local'`
- **[kinetic_k8s.ironic_db_user_setup](#module-kinetic_k8s.ironic_db_user_setup)** - Sets up database users for Ironic.
  - **Example**: `salt '*' kinetic_k8s.ironic_db_user_setup name='ironic-user' namespace='openstack' db_name='ironic' password='dbpass'`
- **[kinetic_k8s.mariadb_database_present](#module-kinetic_k8s.mariadb_database_present)** - Manages MariaDB databases.
  - **Example**: `salt '*' kinetic_k8s.mariadb_database_present name='ironic-db' namespace='openstack' instance='mariadb1'`
- **[kinetic_k8s.generate_tls_secret](#module-kinetic_k8s.generate_tls_secret)** - Generates TLS secrets for secure communication.
  - **Example**: `salt '*' kinetic_k8s.generate_tls_secret name='tls-secret' namespace='openstack' cert_path='/path/to/cert' key_path='/path/to/key'`
- **[kinetic_k8s.check_ironic_operator](#module-kinetic_k8s.check_ironic_operator)** - Checks the status of the Ironic operator.
  - **Example**: `salt '*' kinetic_k8s.check_ironic_operator namespace='openstack'`
- **[kinetic_k8s.ironic_instance_present](#module-kinetic_k8s.ironic_instance_present)** - Manages Ironic instances for bare metal provisioning.
  - **Example**: `salt '*' kinetic_k8s.ironic_instance_present name='ironic1' namespace='openstack' replicas=1`
- **[kinetic_k8s.image_server_present](#module-kinetic_k8s.image_server_present)** - Configures image servers for use in deployments.
  - **Example**: `salt '*' kinetic_k8s.image_server_present name='image-server' namespace='openstack' url='http://images.example.com'`
- **[kinetic_k8s.bmh_state](#module-kinetic_k8s.bmh_state)** - Retrieves or sets the state of Bare Metal Hosts.
  - **Example**: `salt '*' kinetic_k8s.bmh_state name='host1' namespace='openstack' state='ready'`
- **[kinetic_k8s.namespace_present](#module-kinetic_k8s.namespace_present)** - Manages Kubernetes namespaces.
  - **Example**: `salt '*' kinetic_k8s.namespace_present name='openstack'`
- **[kinetic_k8s.ceph_cluster_present](#module-kinetic_k8s.ceph_cluster_present)** - Configures Ceph clusters for storage.
  - **Example**: `salt '*' kinetic_k8s.ceph_cluster_present name='ceph1' namespace='openstack' nodes=3 storage_size='20Gi'`
- **[kinetic_k8s.configmap_present](#module-kinetic_k8s.configmap_present)** - Manages Kubernetes ConfigMaps.
  - **Example**: `salt '*' kinetic_k8s.configmap_present name='config1' namespace='openstack' data='{"key": "value"}'`
- **[kinetic_k8s.service_present](#module-kinetic_k8s.service_present)** - Manages Kubernetes Services.
  - **Example**: `salt '*' kinetic_k8s.service_present name='service1' namespace='openstack' type='ClusterIP' ports='[{"port": 80, "targetPort": 8080}]'`
- **[kinetic_k8s.node_label_present](#module-kinetic_k8s.node_label_present)** - Applies labels to Kubernetes nodes.
  - **Example**: `salt '*' kinetic_k8s.node_label_present name='node1' label='role=worker'`
- **[kinetic_k8s.metallb_pool_present](#module-kinetic_k8s.metallb_pool_present)** - Configures MetalLB IP address pools.
  - **Example**: `salt '*' kinetic_k8s.metallb_pool_present name='ip-pool1' namespace='metallb-system' addresses='["192.168.1.100-192.168.1.110"]'`
- **[kinetic_k8s.metallb_l2_advertisement_present](#module-kinetic_k8s.metallb_l2_advertisement_present)** - Manages MetalLB L2 advertisements.
  - **Example**: `salt '*' kinetic_k8s.metallb_l2_advertisement_present name='l2-ad1' namespace='metallb-system' pools='["ip-pool1"]'`
- **[kinetic_k8s.certmanager_issuer_present](#module-kinetic_k8s.certmanager_issuer_present)** - Configures Cert-Manager issuers for certificate management.
  - **Example**: `salt '*' kinetic_k8s.certmanager_issuer_present name='issuer1' namespace='openstack' kind='selfSigned'`
- **[kinetic_k8s.ingress_present](#module-kinetic_k8s.ingress_present)** - Manages Kubernetes Ingress resources.
  - **Example**: `salt '*' kinetic_k8s.ingress_present name='ingress1' namespace='openstack' host='example.com' service='service1' port=80`
- **[kinetic_k8s.certmanager_certificate_present](#module-kinetic_k8s.certmanager_certificate_present)** - Manages certificates via Cert-Manager.
  - **Example**: `salt '*' kinetic_k8s.certmanager_certificate_present name='cert1' namespace='openstack' issuer='issuer1' common_name='example.com'`
- **[kinetic_k8s.cnpg_cluster_present](#module-kinetic_k8s.cnpg_cluster_present)** - Configures CloudNativePG clusters for PostgreSQL.
  - **Example**: `salt '*' kinetic_k8s.cnpg_cluster_present name='postgres1' namespace='openstack' instances=2 storage_size='10Gi'`
- **[kinetic_k8s.secret_present](#module-kinetic_k8s.secret_present)** - Manages Kubernetes Secrets.
  - **Example**: `salt '*' kinetic_k8s.secret_present name='secret1' namespace='openstack' data='{"password": "mypassword"}'`
- **[kinetic_k8s.keycloak_cluster_present](#module-kinetic_k8s.keycloak_cluster_present)** - Configures Keycloak clusters for identity and access management.
  - **Example**: `salt '*' kinetic_k8s.keycloak_cluster_present name='keycloak1' namespace='openstack' replicas=1 admin_user='admin' admin_password='adminpass'`
- **[kinetic_k8s.certificate_present](#module-kinetic_k8s.certificate_present)** - Manages certificates directly.
  - **Example**: `salt '*' kinetic_k8s.certificate_present name='direct-cert' namespace='openstack' cert_data='base64-cert-data' key_data='base64-key-data'`
- **[kinetic_k8s.pvc_present](#module-kinetic_k8s.pvc_present)** - Manages Persistent Volume Claims (PVC) in Kubernetes.
  - **Example**: `salt '*' kinetic_k8s.pvc_present name='pvc1' namespace='openstack' size='5Gi' s
