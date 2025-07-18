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
    - user: root
    - group: root
    - dir_mode: 755
    - file_mode: 644

ensure_k8s_storage:
  k8s.local_storage_pv_pvc_present:
    - namespace: {{ pillar['bmo_namespace'] }}
    - pv_name: {{ pillar['ironic_db_dir'] }}
    - pvc_name: {{ pillar['ironic_db_dir'] }}
    - storage_size: 5Gi
    - node_name: {{ grains['id'] }}
    - path: {{ pillar['ironic_db_dir'] }}
    - require:
      - file: create_ironic_db_dir
  
ensure_mariadb_instance:
  k8s.mariadb_instance_present:
    - namespace: {{ pillar['bmo_namespace'] }}
    - instance_name: ironic-mariadb
    - root_password: {{ pillar['ironic_password'] }}
    - secret_name: mariadb-root-password
    - image: mariadb:10.6
    - pvc_name: {{ pillar['ironic_db_dir'] }}
    - replicas: 1
    - limits_cpu: 500m
    - limits_memory: 512Mi
    - requests_cpu: 200m
    - requests_memory: 256Mi
    - require:
     - k8s: local_storage_pv_pvc_present

clone_ironic_repo:
  git.cloned:
    - name: https://github.com/metal3-io/ironic-standalone-operator
    - branch: {{ pillar['ironic_op_release'] }}
    - target: {{ pillar['ironic_op_dir'] }}
    - require:
      - file: create_ironic_op_dir

