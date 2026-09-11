include:
  - /formulas/heat/install
  - /formulas/osh-helm-repos/configure

{# heat_ingress/cloudformation_ingress hosts may be a list of plain hostname
   strings, or a list of dicts with a 'host' key (the shape historically used
   alongside 'tls' for the old Ingress resource) - normalize to a flat list
   of hostnames either way. #}
{% set heat_hostnames = [] %}
{% for h in pillar['osh']['heat']['heat_ingress']['hosts'] %}
{% if h is mapping %}
{% do heat_hostnames.append(h['host']) %}
{% else %}
{% do heat_hostnames.append(h) %}
{% endif %}
{% endfor %}
{% set cloudformation_hostnames = [] %}
{% for h in pillar['osh']['heat']['cloudformation_ingress']['hosts'] %}
{% if h is mapping %}
{% do cloudformation_hostnames.append(h['host']) %}
{% else %}
{% do cloudformation_hostnames.append(h) %}
{% endif %}
{% endfor %}

# Routes external Heat API traffic through the external Gateway
# (traefik-external, websecure-ext listener). TLS termination happens at
# the Gateway listener - the certificate itself is managed elsewhere, not
# here.
heat_httproute:
  k8s.httproute_present:
    - name: heat-route
    - namespace: openstack
    - parent_refs:
        - name: traefik-external
          namespace: ingress
          sectionName: websecure-ext
    - hostnames: {{ heat_hostnames | tojson }}
    - rules:
        - matches:
            - path:
                type: PathPrefix
                value: "/"
          backendRefs:
            - name: heat-api
              port: 8004

# Routes external Heat CloudFormation (CFN) API traffic the same way.
cloudformation_httproute:
  k8s.httproute_present:
    - name: cloudformation-route
    - namespace: openstack
    - parent_refs:
        - name: traefik-external
          namespace: ingress
          sectionName: websecure-ext
    - hostnames: {{ cloudformation_hostnames | tojson }}
    - rules:
        - matches:
            - path:
                type: PathPrefix
                value: "/"
          backendRefs:
            - name: cfn-api
              port: 8000

install_heat:
  k8s_helm.helm_release_present:
    - release_name: heat
    - chart_name: openstack-helm/heat
    - namespace: openstack
    - wait_timeout: 300
    - wait_interval: 10
    - keep_values_file: true
    - pillar_key: osh:heat:values
    - set_values:
      - endpoints.oslo_db.auth.admin.username=root
      - endpoints.oslo_db.auth.admin.password={{ pillar['osh']['mariadb_admin'] }}
      - endpoints.oslo_db.auth.heat.username=heat
      - endpoints.oslo_db.auth.heat.password={{ pillar['osh']['heat']['users']['heat_admin'] }}
      - endpoints.oslo_messaging.auth.admin.username=rabbitmq
      - endpoints.oslo_messaging.auth.admin.password={{ pillar['osh']['rabbitmq_admin'] }}
      - endpoints.oslo_messaging.auth.heat.username=heat
      - endpoints.oslo_messaging.auth.heat.password={{ pillar['osh']['heat']['users']['heat_rq_user'] }}
      - endpoints.identity.auth.admin.password={{ pillar['osh']['osh_users']['admin'] }}
      - endpoints.identity.auth.heat.password={{ pillar['osh']['heat']['users']['heat_admin'] }}
      - endpoints.identity.auth.heat_trustee.password={{ pillar['osh']['heat']['users']['heat_trust'] }}
      - endpoints.identity.auth.heat_stack_user.password={{ pillar['osh']['heat']['users']['heat_domain'] }}
      - endpoints.identity.auth.test.password={{ pillar['osh']['heat']['users']['heat_test'] }}
    - require:
      - k8s: heat_httproute
      - k8s: cloudformation_httproute

cleanup_completed_jobs:
  k8s.job_cleanup:
    - namespace: openstack
    - require:
      - k8s_helm: install_heat
