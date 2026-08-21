include:
  - /formulas/swift/install
  - /formulas/osh-helm-repos/configure

swift_external_certificate:
  k8s.certmanager_certificate_present:
    - name: swift-tls-public
    - certificate_name: swift-tls-public
    - namespace: rook-ceph
    - secret_name: swift-tls-public
    - issuer_name: letsencrypt-prod
    - issuer_kind: ClusterIssuer
    - common_name: {{ pillar['osh_values']['swift_cert']['common_name'] }}
    - dns_names: {{ pillar['osh_values']['swift_cert']['dns_names'] }}

swift_internal_certificate:
  k8s.certmanager_certificate_present:
    - name: swift-internal-proxy
    - certificate_name: swift-internal-proxy
    - namespace: rook-ceph
    - secret_name: swift-internal-proxy
    - issuer_name: cyberrange-ca-issuer
    - issuer_kind: ClusterIssuer
    - common_name: {{ pillar['osh_values']['swift_internal_proxy']['common_name'] }}
    - dns_names: {{ pillar['osh_values']['swift_internal_proxy']['dns_names'] }}

swift_ingress:
  k8s.ingress_present:
    - name: swift-ingress
    - namespace: rook-ceph
    - ingress_class_name: {{ pillar['osh_values']['swift_ingress']['class_name'] }}
    - hosts: {{ pillar['osh_values']['swift_ingress']['hosts'] }}
    - tls: {{ pillar['osh_values']['swift_ingress']['tls'] }}
    - require:
      - k8s: swift_external_certificate

deploy_ceph_object_store:
  k8s.ceph_object_store_present:
    - name: rsc-object-store
    - namespace: rook-ceph
    - replicas: 3
    - port: 80
    - ssl_enabled: false
    - gateway_instances: 2
    - enable_swift_api: true
    - swift_port: 8080
    - swift_account_in_url: true
    - swift_url_prefix: "swift"
    - enable_s3_api: true
    - preserve_pools_on_delete: true
    - auth_keystone: true
    - keystone_url: "http://keystone-api.openstack.svc.cluster.local:5000"
    - keystone_accepted_roles:
        - admin
        - member
        - service
    - keystone_implicit_tenants: "swift"
    - keystone_revocation_interval: 1200
    - keystone_service_user_secret_name: "keystone-admin"
    - keystone_token_cache_size: 1000
    - gateway_resources:
        limits:
          cpu: "500m"
          memory: "512Mi"
        requests:
          cpu: "200m"
          memory: "256Mi"
