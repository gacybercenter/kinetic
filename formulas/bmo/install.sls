include:
  - /formulas/common/k8s-certmanager/install
  - /formulas/common/vbmc
  - /formulas/common/k8s-mariadb
  - /formulas/ironic-operator

ingress_values:
  file.managed:
    - name: /tmp/ingress-values.yaml
    - source: salt://formulas/bmo/files/ingress-values.j2
    - template: jinja

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
    - pvc_name: {{ pillar['ironic_db_dir'] }}-pvc
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
    - replicas: 1
    - limits_cpu: 500m
    - limits_memory: 512Mi
    - requests_cpu: 200m
    - requests_memory: 256Mi
    - admin_host_access: 192.168.1.41
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
    - user_name: {{ pillar.get('ironic-user', pillar['ironic_username']) }}
    - user_password: {{ pillar.get('ironic_user_password', pillar['ironic_password']) }}
    - secret_name: ironic-user
    - database_name: ironic
    - host: '%'
    - max_user_connections: 100
    - privileges:
      - ALL PRIVILEGES
    - table: '*'
    - require:
      - k8s: ensure_mariadb_instance

helm_ingress_repo:
  helm.repo_managed:
    - present:
      - name: nginx-ingress
        url: https://kubernetes.github.io/ingress-nginx
        repo_update: true

helm_ingress_release:
  helm.release_present:
    - name: nginx-ingress
    - chart: ingress-nginx/ingress-nginx
    - namespace: {{ pillar['bmo_namespace'] }}
    - kvflags:
        values: /tmp/ingress-values.yaml
    - unless: helm list -n {{ pillar['bmo_namespace'] }} |grep nginx-ingress
    - require:
      - file: ingress_values
    - watch:
      - file: ingress_values

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
    - name: {{ pillar['ironic_db_dir'] }}
    - dir_mode: 755
    - file_mode: 644

ensure_image_storage:
  k8s.local_storage_pv_pvc_present:
    - namespace: {{ pillar['bmo_namespace'] }}
    - pv_name: {{ pillar['ironic_image_dir'] }}-pv
    - pvc_name: {{ pillar['ironic_image_dir'] }}-pvc
    - storage_size: 10Gi
    - path: {{ pillar['ironic_image_dir'] }}
    - storage_class: local-storage
    - require:
      - file: create_ironic_image_dir

ensure_image_server:
  k8s.image_server_present:
    - name: ensure_image_server
    - namespace: {{ pillar['bmo_namespace'] }}
    - port: 6182
    - storage_size: "10Gi"
    - storage_path: {{ pillar['ironic_image_dir'] }}
    - storage_class: "local-storage"
    - service_type: LoadBalancer
    - external_ip: 10.150.1.41
