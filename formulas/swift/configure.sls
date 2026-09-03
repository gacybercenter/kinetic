include:
  - /formulas/keystone/federation
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
{% set swift_public_hostname = pillar['osh'].get('swift_public_hostname', swift_hostnames[0] if swift_hostnames else 'swift.rsc.gacyberrange.org') %}
{% set swift_region = pillar['osh'].get('swift_region', 'RegionOne') %}
{% set swift_cloud = pillar['osh']['cloud'] %}

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

# Admin credentials RGW uses to authenticate itself against Keystone (NOT
# an end-user's credentials). Referenced by deploy_ceph_object_store's
# keystone_service_user_secret_name. Rook/RGW requires this exact set of
# OS_* keys (matching an OpenStack `openrc` file) - a plain username/
# password pair is not sufficient. See:
# https://rook.io/docs/rook/latest/Storage-Configuration/Object-Storage-RGW/ceph-object-swift/
keystone_admin_secret:
  k8s.secret_present:
    - namespace: rook-ceph
    - secret_name: keystone-admin
    - data:
        OS_AUTH_TYPE: "password"
        OS_IDENTITY_API_VERSION: "3"
        OS_USERNAME: "keystone"
        OS_PASSWORD: {{ pillar['osh']['keystone_admin'] | yaml_dquote }}
        OS_PROJECT_NAME: "admin"
        OS_PROJECT_DOMAIN_NAME: "Default"
        OS_USER_DOMAIN_NAME: "Default"

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
    - require:
      - k8s: keystone_admin_secret

# Keystone service catalog entry + endpoints for Swift. The admin/internal
# interfaces point directly at the in-cluster RGW Service (plain HTTP - the
# object store itself has ssl_enabled: false/port 80, so https:// would not
# work here). The public interface goes through swift_httproute above,
# where the external Gateway terminates TLS.
swift_service:
  kinetic_openstack.service_present:
    - name: swift
    - type: object-store
    - description: "Swift Object Storage"
    - cloud: {{ swift_cloud }}
    - require:
      - kinetic_openstack: keystone_available

# Keystone endpoints require region_id to reference an existing Region -
# it is not a free-form string, despite what it may look like from the API.
swift_region:
  kinetic_openstack.region_present:
    - name: {{ swift_region }}
    - cloud: {{ swift_cloud }}
    - require:
      - kinetic_openstack: keystone_available

swift_endpoint_admin:
  kinetic_openstack.endpoint_present:
    - service_name: swift
    - interface: admin
    - region: {{ swift_region }}
    - url: "http://rook-ceph-rgw-rsc-object-store.rook-ceph.svc.cluster.local/swift/v1"
    - cloud: {{ swift_cloud }}
    - require:
      - kinetic_openstack: swift_service
      - kinetic_openstack: swift_region

swift_endpoint_internal:
  kinetic_openstack.endpoint_present:
    - service_name: swift
    - interface: internal
    - region: {{ swift_region }}
    - url: "http://rook-ceph-rgw-rsc-object-store.rook-ceph.svc.cluster.local/swift/v1"
    - cloud: {{ swift_cloud }}
    - require:
      - kinetic_openstack: swift_service
      - kinetic_openstack: swift_region

swift_endpoint_public:
  kinetic_openstack.endpoint_present:
    - service_name: swift
    - interface: public
    - region: {{ swift_region }}
    - url: "https://{{ swift_hostnames[0] }}/swift/v1"
    - cloud: {{ swift_cloud }}
    - require:
      - kinetic_openstack: swift_service
      - kinetic_openstack: swift_region
      - k8s: swift_httproute
