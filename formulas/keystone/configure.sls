include:
  - /formulas/keystone/install
  - /formulas/osh-helm-repos/configure

keystone_external_certificate:
  k8s.certmanager_certificate_present:
    - name: keystone-tls
    - certificate_name: keystone-tls
    - namespace: openstack
    - secret_name: keystone-tls
    - issuer_name: letsencrypt-prod
    - issuer_kind: ClusterIssuer
    - common_name: {{ pillar['osh_values']['keystone_cert']['common_name'] }}
    - dns_names: {{ pillar['osh_values']['keystone_cert']['dns_names'] }}

keystone_internal_certificate:
  k8s.certmanager_certificate_present:
    - name: keystone-tls-api
    - certificate_name: keystone-tls-api
    - namespace: openstack
    - secret_name: keystone-tls-api
    - issuer_name: cyberrange-ca-issuer
    - issuer_kind: ClusterIssuer
    - common_name: {{ pillar['osh_values']['keystone_internal_api']['common_name'] }}
    - dns_names: {{ pillar['osh_values']['keystone_internal_api']['dns_names'] }}

keystone_ingress:
  k8s.ingress_present:
    - name: keystone-ingress
    - namespace: openstack
    - hosts: {{ pillar['osh_values']['keystone_ingress']['hosts'] }}
    - tls: {{ pillar['osh_values']['keystone_ingress']['tls'] }}
    - require:
      - k8s: keystone_external_certificate

install_keystone:
  k8s_helm.helm_release_present:
    - release_name: keystone
    - chart_name: openstack-helm/keystone
    - namespace: openstack
    - wait_timeout: 300
    - wait_interval: 10
    - keep_values_file: false
    - pillar_key: osh_values:keystone
    - set_values:
      - endpoints.oslo_db.auth.admin.username=root
      - endpoints.oslo_db.auth.admin.password={{ pillar['osh_values']['mariadb_admin'] }}
      - endpoints.oslo_db.auth.keystone.username=keystone
      - endpoints.oslo_db.auth.keystone.password={{ pillar['osh_values']['keystone_admin'] }}
      - endpoints.oslo_messaging.auth.admin.username=rabbitmq
      - endpoints.oslo_messaging.auth.admin.password={{ pillar['osh_values']['rabbitmq_admin'] }}
      - endpoints.oslo_messaging.auth.keystone.username=keystone
      - endpoints.oslo_messaging.auth.keystone.password={{ pillar['osh_values']['keystone-rq-user'] }}
      - endpoints.identity.auth.admin.password={{ pillar['osh_users']['admin'] }}
      - endpoints.identity.auth.test.password={{ pillar['osh_users']['test'] }}
      - conf.ks_domains.ldap.ldap.password={{ pillar['ldap']['admin-user']['password'] }}
    - require:
      - k8s: keystone_external_certificate
      - k8s: keystone_ingress
