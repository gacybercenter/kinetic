include:
  /formulas/common/helm

helm_mariadb_op_repo:
  helm.repo_managed:
    - present:
      - name: mariadb-operator
        url: https://helm.mariadb.com/mariadb-operator
        repo_update: true
helm_mariadb_crds_release:
  helm.release_present:
    - name: mariadb-operator-crds
    - chart: mariadb-operator/mariadb-operator-crds
    - namespace: {{ pillar['bmo_namespace'] }}
    - unless: helm list -n {{ pillar['bmo_namespace'] }} |grep mariadb-operator-crds
helm_mariadb_op_release:
  helm.release_present:
    - name: mariadb-operator
    - chart: mariadb-operator/mariadb-operator
    - namespace: {{ pillar['bmo_namespace'] }}
    - unless: helm list -n {{ pillar['bmo_namespace'] }} |grep mariadb-operator