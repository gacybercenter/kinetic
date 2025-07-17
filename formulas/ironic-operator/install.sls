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
  

  
clone_ironic_repo:
  git.cloned:
    - name: https://github.com/metal3-io/ironic-standalone-operator
    - branch: {{ pillar['ironic_op_release'] }}
    - target: {{ pillar['ironic_data_dir'] }}
    - require:
      - file: create_ironic_op_dir

