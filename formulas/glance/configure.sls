include:
  - /formulas/glance/install
  - /formulas/osh-helm-repos/configure

glance_external_certificate:
  k8s.certmanager_certificate_present:
    - name: glance-tls-public
    - certificate_name: glance-tls-public
    - namespace: openstack
    - secret_name: glance-tls-public
    - issuer_name: letsencrypt-prod
    - issuer_kind: ClusterIssuer
    - common_name: {{ pillar['osh_values']['glance_cert']['common_name'] }}
    - dns_names: {{ pillar['osh_values']['glance_cert']['dns_names'] }}

glance_internal_certificate:
  k8s.certmanager_certificate_present:
    - name: glance-tls-api
    - certificate_name: glance-tls-api
    - namespace: openstack
    - secret_name: glance-tls-api
    - issuer_name: cyberrange-ca-issuer
    - issuer_kind: ClusterIssuer
    - common_name: {{ pillar['osh_values']['glance_internal_api']['common_name'] }}
    - dns_names: {{ pillar['osh_values']['glance_internal_api']['dns_names'] }}

glance_ingress:
  k8s.ingress_present:
    - name: glance-ingress
    - namespace: openstack
    - ingress_class_name: {{ pillar['osh_values']['glance_ingress']['class_name'] }}
    - hosts: {{ pillar['osh_values']['glance_ingress']['hosts'] }}
    - tls: {{ pillar['osh_values']['glance_ingress']['tls'] }}
    - require:
      - k8s: glance_external_certificate

install_glance:
  k8s_helm.helm_release_present:
    - release_name: glance
    - chart_name: openstack-helm/glance
    - namespace: openstack
    - wait_timeout: 300
    - wait_interval: 10
    - keep_values_file: true
    - pillar_key: osh:glance
    - set_values:
      - endpoints.oslo_db.auth.admin.username=root
      - endpoints.oslo_db.auth.admin.password={{ pillar['osh']['mariadb_admin'] }}
      - endpoints.oslo_db.auth.glance.username=glance
      - endpoints.oslo_db.auth.glance.password={{ pillar['osh']['glance_admin'] }}
      - endpoints.oslo_messaging.auth.admin.username=rabbitmq
      - endpoints.oslo_messaging.auth.admin.password={{ pillar['osh']['rabbitmq_admin'] }}
      - endpoints.oslo_messaging.auth.glance.username=glance
      - endpoints.oslo_messaging.auth.glance.password={{ pillar['osh']['glance_rq_user'] }}
      - endpoints.identity.auth.admin.password={{ pillar['osh']['admin'] }}
      - endpoints.identity.auth.glance.password={{ pillar['osh']['glance_admin'] }}
      - endpoints.identity.auth.test.password={{ pillar['osh']['glance_test'] }}
    - require:
      - k8s: glance_external_certificate
      - k8s: glance_ingress
