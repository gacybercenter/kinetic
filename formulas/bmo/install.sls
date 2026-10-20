include:
  - /formulas/common/k8s-certmanager/install
  - /formulas/common/vbmc
  - /formulas/common/k8s-mariadb
  - /formulas/ironic-operator

{# One Gateway in this namespace — not the dual Traefik/MetalLB stack from
   formulas/common/k8s-ingress-controller. Override hostnames from pillar. #}
{% set ironic_api_hosts = pillar.get('ironic_api_hosts', [pillar.get('ironic_api_host', 'ironic.rsc.gacyberrange.org')]) %}
{% set ironic_image_hosts = pillar.get('ironic_image_hosts', [pillar.get('ironic_image_host', 'images.rsc.gacyberrange.org')]) %}

# Install dependencies (kustomize, kubectl)
install_dependencies:
  pkg.installed:
    - pkgs:
        - kubectl
        - curl
        - apache2-utils
        - golang
        - libvirt-dev
        - pkg-config
  cmd.run:
    - name: |
        curl -sL https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.4.1/kustomize_v5.4.1_linux_amd64.tar.gz | tar xz -C /usr/local/bin/ && chmod +x /usr/local/bin/kustomize
    - unless: test -x /usr/local/bin/kustomize && kustomize version | grep v5.4.1
    - require:
      - pkg: install_dependencies
salt-pip_installs:
  pip.installed:
    - bin_env: '/usr/bin/salt-pip'
    - reload_modules: true
    - names:
      - libvirt-python
    - require:
      - pkg: install_dependencies

bmo_namespace_present:
  cmd.run:
    - name: kubectl create ns {{ pillar['bmo_namespace'] }}
    - unless: kubectl get ns |grep {{ pillar['bmo_namespace'] }}

create_ironic_db_dir:
  file.directory:
    - name: {{ pillar['ironic_db_dir'] }}
    - user: 999
    - group: 999
    - dir_mode: 755
    - file_mode: 644
    - require:
      - sls: /formulas/common/k8s-mariadb/install

ensure_k8s_storage:
  k8s.local_storage_pv_pvc_present:
    - namespace: {{ pillar['bmo_namespace'] }}
    - pv_name: {{ pillar['ironic_db_dir'] }}-pv
    {# mariadb-operator names the data PVC storage-<MariaDB.metadata.name>-0 #}
    - pvc_name: storage-ironic-mariadb-0
    - storage_size: 5Gi
    - path: {{ pillar['ironic_db_dir'] }}
    - storage_class: local-storage
    - require:
      - file: create_ironic_db_dir

ensure_mariadb_instance:
  k8s.mariadb_instance_present:
    - namespace: {{ pillar['bmo_namespace'] }}
    - instance_name: ironic-mariadb
    - root_password: {{ pillar['ironic_password'] }}
    - secret_name: mariadb-root-password
    - image: mariadb:10.6
    - storage_size: 5Gi
    - storage_class: local-storage
    - pvc_name: storage-ironic-mariadb-0
    - replicas: 1
    - limits_cpu: 500m
    - limits_memory: 512Mi
    - requests_cpu: 200m
    - requests_memory: 256Mi
    {# Ironic speaks plaintext MySQL unless database.tlsCertificateName is set. #}
    - tls_enabled: false
    {# Default MariaDB packet size is 16M; Ironic schema/db sync can abort
       connections with "Got an error reading communication packets". #}
    - max_allowed_packet: 256M
    - require:
      - k8s: ensure_k8s_storage

ensure_ironic_database:
  k8s.mariadb_database_present:
    - namespace: {{ pillar['bmo_namespace'] }}
    - database_name: ironic
    - mariadb_name: ironic-mariadb
    - mariadb_namespace: {{ pillar['bmo_namespace'] }}
    - character_set: utf8
    - collate: utf8_general_ci
    - cleanup_policy: Delete
    - require:
      - k8s: ensure_mariadb_instance

ensure_ironic_db_user:
  k8s.ironic_db_user_present:
    - namespace: {{ pillar['bmo_namespace'] }}
    - mariadb_name: ironic-mariadb
    - mariadb_namespace: {{ pillar['bmo_namespace'] }}
    - user_name: {{ pillar['ironic_username'] }}
    - user_password: {{ pillar['ironic_password'] }}
    - secret_name: ironic-user
    - database_name: ironic
    - host: '%'
    - max_user_connections: 100
    - privileges:
      - ALL PRIVILEGES
    - table: '*'
    - require:
      - k8s: ensure_mariadb_instance

helm_traefik_repo:
  k8s_helm.helm_repo_present:
    - repo_name: traefik
    - repo_url: https://traefik.github.io/charts
    - update_cache: true

# Single Traefik + Gateway API for BMO only. VIP is kube-vip (--services),
# not MetalLB. Do not include formulas/common/k8s-ingress-controller.
install_bmo_gateway_controller:
  k8s_helm.helm_release_present:
    - release_name: traefik-bmo
    - chart_name: traefik/traefik
    - namespace: {{ pillar['bmo_namespace'] }}
    - values_dict:
        providers:
          kubernetesIngress:
            enabled: false
          kubernetesCRD:
            enabled: false
          kubernetesGateway:
            enabled: true
        gateway:
          enabled: false
        ports:
          web:
            port: 8000
            expose:
              default: true
            exposedPort: 80
          websecure:
            port: 8443
            expose:
              default: true
            exposedPort: 443
        service:
          type: LoadBalancer
          spec:
            loadBalancerClass: kube-vip.io/kube-vip-class
            loadBalancerIP: "{{ pillar['ironic_endpoint_ip'] }}"
          annotations:
            kube-vip.io/loadbalancerIPs: "{{ pillar['ironic_endpoint_ip'] }}"
    - wait_timeout: 300
    - wait_interval: 10
    - require:
      - k8s_helm: helm_traefik_repo
      - cmd: bmo_namespace_present

clone_bmo_repo:
  git.cloned:
    - name: https://github.com/metal3-io/baremetal-operator.git
    - branch: {{ pillar['bmo_version'] }}
    - target: {{ pillar['script_dir'] }}
    - require:
      - pkg: install_dependencies
    - unless: -f {{ pillar['script_dir'] }}

create_ironic_image_dir:
  file.directory:
    - name: {{ pillar['ironic_image_dir'] }}
    - dir_mode: 755
    - file_mode: 644

ensure_image_storage:
  k8s.local_storage_pv_pvc_present:
    - namespace: {{ pillar['bmo_namespace'] }}
    - pv_name: ironic-images-pv
    - pvc_name: ironic-images-pvc
    - storage_size: 10Gi
    - path: {{ pillar['ironic_image_dir'] }}
    - storage_class: local-storage
    - require:
      - file: create_ironic_image_dir

# Reuses ironic-images-pvc from ensure_image_storage (do not create a second claim).
ensure_image_server:
  k8s.image_server_present:
    - name: ensure_image_server
    - namespace: {{ pillar['bmo_namespace'] }}
    - port: 6182
    - pvc_name: ironic-images-pvc
    - storage_size: "10Gi"
    - storage_path: {{ pillar['ironic_image_dir'] }}
    - storage_class: "local-storage"
    - service_type: ClusterIP
    - require:
      - k8s: ensure_image_storage

# HTTP + HTTPS listeners. Traefik Gateway API matches listener.port to the
# entryPoint *container* port (8000/8443), not Service exposedPort 80/443.
# TLS is optional until ironic-tls exists (created in configure.sls).
bmo_gateway:
  k8s.gateway_present:
    - name: bmo-gateway
    - namespace: {{ pillar['bmo_namespace'] }}
    - gateway_class_name: traefik
    - listeners:
        - name: web
          protocol: HTTP
          port: 8000
          allowedRoutes:
            namespaces:
              from: Same
        - name: websecure
          protocol: HTTPS
          port: 8443
          allowedRoutes:
            namespaces:
              from: Same
          tls:
            mode: Terminate
            certificateRefs:
              - kind: Secret
                name: ironic-tls
                group: ""
    - require:
      - k8s_helm: install_bmo_gateway_controller

ironic_httproute:
  k8s.httproute_present:
    - name: ironic-route
    - namespace: {{ pillar['bmo_namespace'] }}
    - parent_refs:
        - name: bmo-gateway
          namespace: {{ pillar['bmo_namespace'] }}
          sectionName: websecure
    - hostnames: {{ ironic_api_hosts | tojson }}
    - rules:
        - matches:
            - path:
                type: PathPrefix
                value: "/"
          backendRefs:
            - name: ironic
              port: 443
    - require:
      - k8s: bmo_gateway

image_httproute:
  k8s.httproute_present:
    - name: ironic-images-route
    - namespace: {{ pillar['bmo_namespace'] }}
    - parent_refs:
        - name: bmo-gateway
          namespace: {{ pillar['bmo_namespace'] }}
          sectionName: web
    - hostnames: {{ ironic_image_hosts | tojson }}
    - rules:
        - matches:
            - path:
                type: PathPrefix
                value: "/"
          backendRefs:
            - name: ironic-image-server
              port: 6182
    - require:
      - k8s: bmo_gateway
      - k8s: ensure_image_server
