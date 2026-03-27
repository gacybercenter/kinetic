include:
  - /formulas/heat/install
  - /formulas/osh-helm-repos/configure

heat_external_certificate:
  k8s.certmanager_certificate_present:
    - name: heat-tls-public
    - certificate_name: heat-tls-public
    - namespace: openstack
    - secret_name: heat-tls-public
    - issuer_name: letsencrypt-prod
    - issuer_kind: ClusterIssuer
    - common_name: {{ pillar['osh_values']['heat_cert']['common_name'] }}
    - dns_names: {{ pillar['osh_values']['heat_cert']['dns_names'] }}

heat_internal_certificate:
  k8s.certmanager_certificate_present:
    - name: heat-tls-api
    - certificate_name: heat-tls-api
    - namespace: openstack
    - secret_name: heat-tls-api
    - issuer_name: cyberrange-ca-issuer
    - issuer_kind: ClusterIssuer
    - common_name: {{ pillar['osh_values']['heat_internal_api']['common_name'] }}
    - dns_names: {{ pillar['osh_values']['heat_internal_api']['dns_names'] }}

cloudformation_external_certificate:
  k8s.certmanager_certificate_present:
    - name: cloudformation-tls-public
    - certificate_name: cloudformation-tls-public
    - namespace: openstack
    - secret_name: cloudformation-tls-public
    - issuer_name: letsencrypt-prod
    - issuer_kind: ClusterIssuer
    - common_name: {{ pillar['osh_values']['heat_cloudformation_cert']['common_name'] }}
    - dns_names: {{ pillar['osh_values']['heat_cloudformation_cert']['dns_names'] }}

cfn_internal_certificate:
  k8s.certmanager_certificate_present:
    - name: heat-tls-cfn
    - certificate_name: heat-tls-cfn
    - namespace: openstack
    - secret_name: heat-tls-cfn
    - issuer_name: cyberrange-ca-issuer
    - issuer_kind: ClusterIssuer
    - common_name: {{ pillar['osh_values']['heat_cfn']['common_name'] }}
    - dns_names: {{ pillar['osh_values']['heat_cfn']['dns_names'] }}

heat_ingress:
  k8s.ingress_present:
    - name: heat-ingress
    - namespace: openstack
    - ingress_class_name: {{ pillar['osh_values']['heat_ingress']['class_name'] }}
    - hosts: {{ pillar['osh_values']['heat_ingress']['hosts'] }}
    - tls: {{ pillar['osh_values']['heat_ingress']['tls'] }}
    - require:
      - k8s: heat_external_certificate

cloudformation_ingress:
  k8s.ingress_present:
    - name: cloudformation-ingress
    - namespace: openstack
    - ingress_class_name: {{ pillar['osh_values']['cloudformation_ingress']['class_name'] }}
    - hosts: {{ pillar['osh_values']['cloudformation_ingress']['hosts'] }}
    - tls: {{ pillar['osh_values']['cloudformation_ingress']['tls'] }}
    - require:
      - k8s: cloudformation_external_certificate

install_heat:
  k8s_helm.helm_release_present:
    - release_name: heat
    - chart_name: openstack-helm/heat
    - namespace: openstack
    - wait_timeout: 300
    - wait_interval: 10
    - keep_values_file: true
    - pillar_key: osh_values:heat
    - set_values:
      - endpoints.oslo_db.auth.admin.username=root
      - endpoints.oslo_db.auth.admin.password={{ pillar['osh_values']['mariadb_admin'] }}
      - endpoints.oslo_db.auth.heat.username=heat
      - endpoints.oslo_db.auth.heat.password={{ pillar['osh_values']['heat_admin'] }}
      - endpoints.oslo_messaging.auth.admin.username=rabbitmq
      - endpoints.oslo_messaging.auth.admin.password={{ pillar['osh_values']['rabbitmq_admin'] }}
      - endpoints.oslo_messaging.auth.heat.username=heat
      - endpoints.oslo_messaging.auth.heat.password={{ pillar['osh_values']['heat_rq_user'] }}
      - endpoints.identity.auth.admin.password={{ pillar['osh_users']['admin'] }}
      - endpoints.identity.auth.heat.password={{ pillar['osh_values']['heat_admin'] }}
      - endpoints.identity.auth.heat_trustee.password={{ pillar['osh_values']['heat_trust'] }}
      - endpoints.identity.auth.heat_stack_user.password={{ pillar['osh_values']['heat_domain'] }}
      - endpoints.identity.auth.test.password={{ pillar['osh_values']['heat_test'] }}
    - require:
      - k8s: heat_external_certificate
      - k8s: cloudformation_external_certificate
      - k8s: heat_ingress
      - k8s: cloudformation_ingress

cleanup_completed_jobs:
  k8s.job_cleanup:
    - namespace: openstack
    - require:
      - k8s_helm: install_heat
