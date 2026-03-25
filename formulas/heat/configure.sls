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
