include:
  - /formulas/osh-mariadb/install
  - /formulas/osh-helm-repos/configure

install_mariadb:
  k8s_helm.helm_release_present:
    - release_name: mariadb
    - chart_name: openstack-helm/mariadb
    - namespace: openstack
    - wait_timeout: 300
    - wait_interval: 10
    - pillar_key: osh_values:mariadb
    - keep_values_file: false
    - set_values:
      - endpoints.oslo_db.auth.admin.username=root
      - endpoints.oslo_db.auth.admin.password={{ pillar['osh_values']['mariadb_admin'] }}
      - endpoints.oslo_db.auth.sst.username=sst
      - endpoints.oslo_db.auth.sst.password={{ pillar['osh_values']['mariadb_sst'] }}
      - endpoints.oslo_db.auth.audit.username=audit
      - endpoints.oslo_db.auth.audit.password={{ pillar['osh_values']['mariadb_audit'] }}
      - endpoints.oslo_db.auth.exporter.username=exporter
      - endpoints.oslo_db.auth.exporter.password={{ pillar['osh_values']['mariadb_exporter'] }}
