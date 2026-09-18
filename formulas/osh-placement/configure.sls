include:
  - /formulas/placement/install
  - /formulas/osh-helm-repos/configure

{# placement_ingress.hosts may be a list of plain hostname strings, or a
   list of dicts with a 'host' key (the shape historically used alongside
   'tls' for the old Ingress resource) - normalize to a flat list of
   hostnames either way. #}
{% set placement_hostnames = [] %}
{% for h in pillar['osh']['placement_ingress']['hosts'] %}
{% if h is mapping %}
{% do placement_hostnames.append(h['host']) %}
{% else %}
{% do placement_hostnames.append(h) %}
{% endif %}
{% endfor %}

# Routes external Placement API traffic through the external Gateway
# (traefik-external, websecure-ext listener). TLS termination happens at
# the Gateway listener - the certificate itself is managed elsewhere, not
# here.
placement_httproute:
  k8s.httproute_present:
    - name: placement-route
    - namespace: openstack
    - parent_refs:
        - name: traefik-external
          namespace: ingress
          sectionName: websecure-ext
    - hostnames: {{ placement_hostnames | tojson }}
    - rules:
        - matches:
            - path:
                type: PathPrefix
                value: "/"
          backendRefs:
            - name: placement-api
              port: 8778

install_placement:
  k8s_helm.helm_release_present:
    - release_name: placement
    - chart_name: openstack-helm/placement
    - namespace: openstack
    - wait_timeout: 300
    - wait_interval: 10
    - keep_values_file: true
    - pillar_key: osh:placement:values
    - set_values:
      - endpoints.oslo_db.auth.admin.username=root
      - endpoints.oslo_db.auth.admin.password={{ pillar['osh']['mariadb_admin'] }}
      - endpoints.oslo_db.auth.placement.username=placement
      - endpoints.oslo_db.auth.placement.password={{ pillar['osh']['placement_users']['placement'] }}
      - endpoints.identity.auth.admin.password={{ pillar['osh']['osh_users']['admin'] }}
      - endpoints.identity.auth.placement.username=placement
      - endpoints.identity.auth.placement.password={{ pillar['osh']['placement_users']['placement'] }}
    - require:
      - k8s: placement_httproute
