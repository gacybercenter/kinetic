include:
  - /formulas/common/k8s-mariadb

create_ironic_op_dir:
  file.directory:
    - name: {{ pillar['ironic_op_dir'] }}
    - user: root
    - group: root
    - dir_mode: 755
    - file_mode: 644

create_ironic_db_dir:
  file.directory:
    - name: {{ pillar['ironic_db_dir'] }}
    - user: 999
    - group: 999
    - dir_mode: 755
    - file_mode: 644

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
    - secret_name: ironic-db-password
    - image: mariadb:10.6
    - storage_size: 5Gi
    - storage_class: local-storage
    - replicas: 1
    - limits_cpu: 500m
    - limits_memory: 512Mi
    - requests_cpu: 200m
    - requests_memory: 256Mi
    - require:
      - k8s: ensure_k8s_storage

ensure_ironic_db_user:
  k8s.ironic_db_user_present:
    - namespace: {{ pillar['bmo_namespace'] }}
    - mariadb_name: generic-mariadb
    - mariadb_namespace: {{ pillar['bmo_namespace'] }}
    - user_name: {{ pillar.get('ironic-user', pillar['ironic_username']) }}
    - user_password: {{ pillar.get('ironic_user_password', pillar['ironic_password']) }}
    - secret_name: ironic-user
    - database_name: ironic-database
    - host: '%'
    - max_user_connections: 100
    - privileges:
      - ALL PRIVILEGES
    - table: '*'
    - require:
      - k8s: ensure_mariadb_instance

git_ironic_repo:
  git.config_set:
    - name: safe.directory
    - value: {{ pillar['ironic_op_dir'] }}
    - global: True

clone_ironic_repo:
  git.cloned:
    - name: https://github.com/metal3-io/ironic-standalone-operator
    - branch: {{ pillar['ironic_op_release'] }}
    - target: {{ pillar['ironic_op_dir'] }}
    - require:
      - file: create_ironic_op_dir

