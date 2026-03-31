include:
  - /formulas/swift/install
  - /formulas/osh-helm-repos/configure

swift_external_certificate:
  k8s.certmanager_certificate_present:
    - name: swift-tls-public
    - certificate_name: swift-tls-public
    - namespace: openstack
    - secret_name: swift-tls-public
    - issuer_name: letsencrypt-prod
    - issuer_kind: ClusterIssuer
    - common_name: {{ pillar['osh_values']['swift_cert']['common_name'] }}
    - dns_names: {{ pillar['osh_values']['swift_cert']['dns_names'] }}

swift_internal_certificate:
  k8s.certmanager_certificate_present:
    - name: swift_internal_proxy
    - certificate_name: swift_internal_proxy
    - namespace: openstack
    - secret_name: swift_internal_proxy
    - issuer_name: cyberrange-ca-issuer
    - issuer_kind: ClusterIssuer
    - common_name: {{ pillar['osh_values']['swift_internal_proxy']['common_name'] }}
    - dns_names: {{ pillar['osh_values']['swift_internal_proxy']['dns_names'] }}

swift_ingress:
  k8s.ingress_present:
    - name: swift-ingress
    - namespace: openstack
    - ingress_class_name: {{ pillar['osh_values']['swift_ingress']['class_name'] }}
    - hosts: {{ pillar['osh_values']['swift_ingress']['hosts'] }}
    - tls: {{ pillar['osh_values']['swift_ingress']['tls'] }}
    - require:
      - k8s: swift_external_certificate

install_swift:
  k8s_helm.helm_release_present:
    - release_name: swift
    - chart_name: openstack-helm/swift
    - namespace: openstack
    - wait_timeout: 300
    - wait_interval: 10
    - keep_values_file: true
    - pillar_key: osh_values:swift
    - set_values:
      - endpoints.oslo_db.auth.admin.username=root
      - endpoints.oslo_db.auth.admin.password={{ pillar['osh_values']['mariadb_admin'] }}
      - endpoints.oslo_db.auth.heat.username=swift
      - endpoints.oslo_db.auth.heat.password={{ pillar['osh_values']['swift_admin'] }}
      - endpoints.identity.auth.admin.password={{ pillar['osh_users']['admin'] }}
      - endpoints.identity.auth.swift.password={{ pillar['osh_values']['swift_admin'] }}
    - require:
      - k8s: glance_external_certificate
      - k8s: glance_ingress
