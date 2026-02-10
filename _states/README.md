## States

The following states are available under `_states/k8s.py`:

- **[k8s.bmh_present](#state-k8s.bmh_present)** - Ensures Bare Metal Host resources are present.
  - **Example**: 
    ```yaml
    bmh_host1:
      k8s.bmh_present:
        - name: host1
        - namespace: openstack
        - bmc_address: ipmi://192.168.1.10
    ```
- **[k8s.networkdata_present](#state-k8s.networkdata_present)** - Ensures network data configurations are present.
  - **Example**: 
    ```yaml
    networkdata_host1:
      k8s.networkdata_present:
        - name: host1-net
        - namespace: openstack
        - interfaces: [{"name": "eth0", "ip": "192.168.1.20"}]
    ```
- **[k8s.userdata_present](#state-k8s.userdata_present)** - Ensures userdata configurations are present for hosts.
  - **Example**: 
    ```yaml
    userdata_host1:
      k8s.userdata_present:
        - name: host1-userdata
        - namespace: openstack
        - userdata: |
            #!/bin/bash
            echo "Setup host"
    ```
- **[k8s.host_bmc_auth_present](#state-k8s.host_bmc_auth_present)** - Ensures BMC authentication is configured for hosts.
  - **Example**: 
    ```yaml
    bmc_auth_host1:
      k8s.host_bmc_auth_present:
        - name: host1-bmc
        - namespace: openstack
        - username: admin
        - password: secret
    ```
- **[k8s.uuids_present](#state-k8s.uuids_present)** - Ensures UUID secrets are present.
  - **Example**: 
    ```yaml
    uuids_secret:
      k8s.uuids_present:
        - name: uuids-secret
        - namespace: openstack
        - uuids: {"host1": "uuid-1234"}
    ```
- **[k8s.mariadb_instance_present](#state-k8s.mariadb_instance_present)** - Ensures MariaDB instances are present in Kubernetes.
  - **Example**: 
    ```yaml
    mariadb_instance:
      k8s.mariadb_instance_present:
        - name: mariadb1
        - namespace: openstack
        - replicas: 1
        - storage_size: 10Gi
    ```
- **[k8s.local_storage_pv_pvc_present](#state-k8s.local_storage_pv_pvc_present)** - Ensures local storage PV and PVC are present.
  - **Example**: 
    ```yaml
    local_storage:
      k8s.local_storage_pv_pvc_present:
        - name: local-storage
        - namespace: openstack
        - size: 5Gi
        - path: /mnt/local
    ```
- **[k8s.ironic_db_user_present](#state-k8s.ironic_db_user_present)** - Ensures database users for Ironic are present.
  - **Example**: 
    ```yaml
    ironic_db_user:
      k8s.ironic_db_user_present:
        - name: ironic-user
        - namespace: openstack
        - db_name: ironic
        - password: dbpass
    ```
- **[k8s.mariadb_database_present](#state-k8s.mariadb_database_present)** - Ensures MariaDB databases are present.
  - **Example**: 
    ```yaml
    mariadb_db:
      k8s.mariadb_database_present:
        - name: ironic-db
        - namespace: openstack
        - instance: mariadb1
    ```
- **[k8s.tls_secret_present](#state-k8s.tls_secret_present)** - Ensures TLS secrets are present for secure communication.
  - **Example**: 
    ```yaml
    tls_secret:
      k8s.tls_secret_present:
        - name: tls-secret
        - namespace: openstack
        - cert_path: /path/to/cert
        - key_path: /path/to/key
    ```
- **[k8s.ironic_operator_present](#state-k8s.ironic_operator_present)** - Ensures the Ironic operator is present.
  - **Example**: 
    ```yaml
    ironic_operator:
      k8s.ironic_operator_present:
        - namespace: openstack
    ```
- **[k8s.ironic_instance_present](#state-k8s.ironic_instance_present)** - Ensures Ironic instances are present for bare metal provisioning.
  - **Example**: 
    ```yaml
    ironic_instance:
      k8s.ironic_instance_present:
        - name: ironic1
        - namespace: openstack
        - replicas: 1
    ```
- **[k8s.image_server_present](#state-k8s.image_server_present)** - Ensures image servers are configured.
  - **Example**: 
    ```yaml
    image_server:
      k8s.image_server_present:
        - name: image-server
        - namespace: openstack
        - url: http://images.example.com
    ```
- **[k8s.bmh_state](#state-k8s.bmh_state)** - Manages the state of Bare Metal Hosts.
  - **Example**: 
    ```yaml
    bmh_state_host1:
      k8s.bmh_state:
        - name: host1
        - namespace: openstack
        - state: ready
    ```
- **[k8s.namespace_present](#state-k8s.namespace_present)** - Ensures Kubernetes namespaces are present.
  - **Example**: 
    ```yaml
    namespace_openstack:
      k8s.namespace_present:
        - name: openstack
    ```
- **[k8s.ceph_cluster_present](#state-k8s.ceph_cluster_present)** - Ensures Ceph clusters are present for storage.
  - **Example**: 
    ```yaml
    ceph_cluster:
      k8s.ceph_cluster_present:
        - name: ceph1
        - namespace: openstack
        - nodes: 3
        - storage_size: 20Gi
    ```
- **[k8s.configmap_present](#state-k8s.configmap_present)** - Ensures Kubernetes ConfigMaps are present.
  - **Example**: 
    ```yaml
    configmap_data:
      k8s.configmap_present:
        - name: config1
        - namespace: openstack
        - data: {"key": "value"}
    ```
- **[k8s.service_present](#state-k8s.service_present)** - Ensures Kubernetes Services are present.
  - **Example**: 
    ```yaml
    service_example:
      k8s.service_present:
        - name: service1
        - namespace: openstack
        - type: ClusterIP
        - ports: [{"port": 80, "targetPort": 8080}]
    ```
- **[k8s.node_label_present](#state-k8s.node_label_present)** - Ensures labels are applied to Kubernetes nodes.
  - **Example**: 
    ```yaml
    node_label_worker:
      k8s.node_label_present:
        - name: node1
        - label: role=worker
    ```
- **[k8s.metallb_pool_present](#state-k8s.metallb_pool_present)** - Ensures MetalLB IP address pools are configured.
  - **Example**: 
    ```yaml
    metallb_pool:
      k8s.metallb_pool_present:
        - name: ip-pool1
        - namespace: metallb-system
        - addresses: ["192.168.1.100-192.168.1.110"]
    ```
- **[k8s.metallb_l2_advertisement_present](#state-k8s.metallb_l2_advertisement_present)** - Ensures MetalLB L2 advertisements are present.
  - **Example**: 
    ```yaml
    metallb_l2_ad:
      k8s.metallb_l2_advertisement_present:
        - name: l2-ad1
        - namespace: metallb-system
        - pools: ["ip-pool1"]
    ```
- **[k8s.certmanager_issuer_present](#state-k8s.certmanager_issuer_present)** - Ensures Cert-Manager issuers are present for certificate management.
  - **Example**: 
    ```yaml
    certmanager_issuer:
      k8s.certmanager_issuer_present:
        - name: issuer1
        - namespace: openstack
        - kind: selfSigned
    ```
- **[k8s.ingress_present](#state-k8s.ingress_present)** - Ensures Kubernetes Ingress resources are present.
  - **Example**: 
    ```yaml
    ingress_example:
      k8s.ingress_present:
        - name: ingress1
        - namespace: openstack
        - host: example.com
        - service: service1
        - port: 80
    ```
- **[k8s.certmanager_certificate_present](#state-k8s.certmanager_certificate_present)** - Ensures certificates are managed via Cert-Manager.
  - **Example**: 
    ```yaml
    certmanager_cert:
      k8s.certmanager_certificate_present:
        - name: cert1
        - namespace: openstack
        - issuer: issuer1
        - common_name: example.com
    ```
- **[k8s.cnpg_cluster_present](#state-k8s.cnpg_cluster_present)** - Ensures CloudNativePG clusters are present for PostgreSQL.
  - **Example**: 
    ```yaml
    cnpg_cluster:
      k8s.cnpg_cluster_present:
        - name: postgres1
        - namespace: openstack
        - instances: 2
        - storage_size: 10Gi
    ```
- **[k8s.secret_present](#state-k8s.secret_present)** - Ensures Kubernetes Secrets are present.
  - **Example**: 
    ```yaml
    secret_data:
      k8s.secret_present:
        - name: secret1
        - namespace: openstack
        - data: {"password": "mypassword"}
    ```
- **[k8s.keycloak_cluster_present](#state-k8s.keycloak_cluster_present)** - Ensures Keycloak clusters are present for identity and access management.
  - **Example**: 
    ```yaml
    keycloak_cluster:
      k8s.keycloak_cluster_present:
        - name: keycloak1
        - namespace: openstack
        - replicas: 1
        - admin_user: admin
        - admin_password: adminpass
    ```
- **[k8s.certificate_present](#state-k8s.certificate_present)** - Ensures certificates are directly managed.
  - **Example**: 
    ```yaml
    direct_certificate:
      k8s.certificate_present:
        - name: direct-cert
        - namespace: openstack
        - cert_data: base64-cert-data
        - key_data: base64-key-data
    ```
- **[k8s.pvc_present](#state-k8s.pvc_present)** - Ensures Persistent Volume Claims are present in Kubernetes.
  - **Example**: 
    ```yaml
    pvc_storage:
      k8s.pvc_present:
        - name: pvc1
        - namespace: openstack
        - size: 5Gi
        - storage_class: standard
