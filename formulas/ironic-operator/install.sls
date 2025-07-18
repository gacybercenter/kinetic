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
  
ensure_mariadb_instance:
  k8s.mariadb_instance_present:
    - namespace: baremetal-operator-system
    - instance_name: ironic-mariadb
    - root_password: mysecurepassword
    - secret_name: mariadb-root-password
    - image: mariadb:10.6
    - storage_size: 5Gi
    - storage_class: local-storage
    - pvc_name: ironic-mariadb
    - replicas: 1
    - limits_cpu: 500m
    - limits_memory: 512Mi
    - requests_cpu: 200m
    - requests_memory: 256Mi

clone_ironic_repo:
  git.cloned:
    - name: https://github.com/metal3-io/ironic-standalone-operator
    - branch: {{ pillar['ironic_op_release'] }}
    - target: {{ pillar['ironic_data_dir'] }}
    - require:
      - file: create_ironic_op_dir

