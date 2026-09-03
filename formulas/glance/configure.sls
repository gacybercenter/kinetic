include:
  - /formulas/glance/install
  - /formulas/osh-helm-repos/configure

{# glance_ingress.hosts may be a list of plain hostname strings, or a list of
   dicts with a 'host' key - normalize to a flat list of hostnames either way. #}
{% set glance_hostnames = [] %}
{% for h in pillar['osh']['glance']['glance_ingress']['hosts'] %}
{% if h is mapping %}
{% do glance_hostnames.append(h['host']) %}
{% else %}
{% do glance_hostnames.append(h) %}
{% endif %}
{% endfor %}

# Routes external Glance API traffic through the external Gateway
# (traefik-external, websecure-ext listener). TLS termination happens at
# the Gateway listener - the certificate itself is managed elsewhere, not
# here.
glance_httproute:
  k8s.httproute_present:
    - name: glance-route
    - namespace: openstack
    - parent_refs:
        - name: traefik-external
          namespace: ingress
          sectionName: websecure-ext
    - hostnames: {{ glance_hostnames | tojson }}
    - rules:
        - matches:
            - path:
                type: PathPrefix
                value: "/"
          backendRefs:
            - name: glance-api
              port: 9292

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
      - endpoints.oslo_db.auth.glance.password={{ pillar['osh']['glance']['values']['glance_admin'] }}
      - endpoints.oslo_messaging.auth.admin.username=rabbitmq
      - endpoints.oslo_messaging.auth.admin.password={{ pillar['osh']['rabbitmq_admin'] }}
      - endpoints.oslo_messaging.auth.glance.username=glance
      - endpoints.oslo_messaging.auth.glance.password={{ pillar['osh']['glance']['values']['glance_rq_user'] }}
      - endpoints.identity.auth.admin.password={{ pillar['osh']['admin'] }}
      - endpoints.identity.auth.glance.password={{ pillar['osh']['glance']['values']['glance_admin'] }}
      - endpoints.identity.auth.test.password={{ pillar['osh']['glance']['values']['glance_test'] }}
    - require:
      - k8s: glance_httproute
