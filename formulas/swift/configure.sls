include:
  - /formulas/swift/install
  - /formulas/osh-helm-repos/configure

{# swift_ingress.hosts may be a list of plain hostname strings, or a list of
   dicts with a 'host' key (the shape historically used alongside 'tls' for
   the old Ingress resource) - normalize to a flat list of hostnames either
   way. #}
{% set swift_hostnames = [] %}
{% for h in pillar['osh']['swift_ingress']['hosts'] %}
{% if h is mapping %}
{% do swift_hostnames.append(h['host']) %}
{% else %}
{% do swift_hostnames.append(h) %}
{% endif %}
{% endfor %}

# Routes external Swift/S3 traffic through the external Gateway
# (traefik-external, websecure-ext listener). TLS termination happens at
# the Gateway listener - the certificate itself is managed elsewhere, not
# here.
swift_httproute:
  k8s.httproute_present:
    - name: swift-route
    - namespace: rook-ceph
    - parent_refs:
        - name: traefik-external
          namespace: ingress
          sectionName: websecure-ext
    - hostnames: {{ swift_hostnames | tojson }}
    - rules:
        - matches:
            - path:
                type: PathPrefix
                value: "/"
          backendRefs:
            - name: rook-ceph-rgw-rsc-object-store
              port: 80
    - require:
      - rook: deploy_ceph_object_store

deploy_ceph_object_store:
  rook.ceph_object_store_present:
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
