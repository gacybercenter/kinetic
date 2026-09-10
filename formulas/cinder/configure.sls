include:
  - /formulas/cinder/install
  - /formulas/osh-helm-repos/configure

{# cinder_ingress.hosts may be a list of plain hostname strings, or a list of
   dicts with a 'host' key - normalize to a flat list of hostnames either way. #}
{% set cinder_hostnames = [] %}
{% for h in pillar['osh']['cinder']['cinder_ingress']['hosts'] %}
{% if h is mapping %}
{% do cinder_hostnames.append(h['host']) %}
{% else %}
{% do cinder_hostnames.append(h) %}
{% endif %}
{% endfor %}

# Routes external Cinder API traffic through the external Gateway
# (traefik-external, websecure-ext listener). TLS termination happens at
# the Gateway listener - the certificate itself is managed elsewhere, not
# here.
cinder_httproute:
  k8s.httproute_present:
    - name: cinder-route
    - namespace: openstack
    - parent_refs:
        - name: traefik-external
          namespace: ingress
          sectionName: websecure-ext
    - hostnames: {{ cinder_hostnames | tojson }}
    - rules:
        - matches:
            - path:
                type: PathPrefix
                value: "/"
          backendRefs:
            - name: cinder-api
              port: 8776

install_cinder:
  k8s_helm.helm_release_present:
    - release_name: cinder
    - chart_name: openstack-helm/cinder
    - namespace: openstack
    - wait_timeout: 300
    - wait_interval: 10
    - keep_values_file: true
    - pillar_key: osh:cinder:values
    - set_values:
      - endpoints.oslo_db.auth.admin.username=root
      - endpoints.oslo_db.auth.admin.password={{ pillar['osh']['mariadb_admin'] }}
      - endpoints.oslo_db.auth.cinder.username=cinder
      - endpoints.oslo_db.auth.cinder.password={{ pillar['osh']['cinder']['users']['cinder'] }}
      - endpoints.oslo_messaging.auth.admin.username=rabbitmq
      - endpoints.oslo_messaging.auth.admin.password={{ pillar['osh']['rabbitmq_admin'] }}
      - endpoints.oslo_messaging.auth.cinder.username=cinder
      - endpoints.oslo_messaging.auth.cinder.password={{ pillar['osh']['cinder']['users']['cinder'] }}
      - endpoints.identity.auth.admin.password={{ pillar['osh']['osh_users']['admin'] }}
      - endpoints.identity.auth.cinder.password={{ pillar['osh']['cinder']['users']['cinder'] }}
      - endpoints.identity.auth.glance.password={{ pillar['osh']['glance']['values']['glance_admin'] }}
      - endpoints.identity.auth.nova.password={{ pillar['osh']['cinder']['users']['cinder_nova'] }}
      - endpoints.identity.auth.swift.password={{ pillar['osh']['cinder']['users']['cinder_swift'] }}
      - endpoints.identity.auth.service.password={{ pillar['osh']['cinder']['users']['cinder_service_user'] }}
      - endpoints.identity.auth.test.password={{ pillar['osh']['cinder']['users']['cinder-test'] }}
    - require:
      - k8s: cinder_httproute
