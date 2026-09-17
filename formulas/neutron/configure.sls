include:
  - /formulas/neutron/install
  - /formulas/osh-helm-repos/configure

{# neutron_ingress.hosts may be a list of plain hostname strings, or a list
   of dicts with a 'host' key (the shape historically used alongside 'tls'
   for the old Ingress resource) - normalize to a flat list of hostnames
   either way. #}
{% set neutron_hostnames = [] %}
{% for h in pillar['osh']['neutron_ingress']['hosts'] %}
{% if h is mapping %}
{% do neutron_hostnames.append(h['host']) %}
{% else %}
{% do neutron_hostnames.append(h) %}
{% endif %}
{% endfor %}

# Routes external Neutron API traffic through the external Gateway
# (traefik-external, websecure-ext listener). TLS termination happens at
# the Gateway listener - the certificate itself is managed elsewhere, not
# here.
neutron_httproute:
  k8s.httproute_present:
    - name: neutron-route
    - namespace: openstack
    - parent_refs:
        - name: traefik-external
          namespace: ingress
          sectionName: websecure-ext
    - hostnames: {{ neutron_hostnames | tojson }}
    - rules:
        - matches:
            - path:
                type: PathPrefix
                value: "/"
          backendRefs:
            - name: neutron-server
              port: 9696

install_neutron:
  k8s_helm.helm_release_present:
    - release_name: neutron
    - chart_name: openstack-helm/neutron
    - namespace: openstack
    - wait_timeout: 300
    - wait_interval: 10
    - keep_values_file: true
    - pillar_key: osh:neutron:values
    - set_values:
      - endpoints.oslo_db.auth.admin.username=root
      - endpoints.oslo_db.auth.admin.password={{ pillar['osh']['mariadb_admin'] }}
      - endpoints.oslo_db.auth.neutron.username=neutron
      - endpoints.oslo_db.auth.neutron.password={{ pillar['osh']['neutron_users']['neutron'] }}
      - endpoints.oslo_messaging.auth.admin.username=rabbitmq
      - endpoints.oslo_messaging.auth.admin.password={{ pillar['osh']['rabbitmq_admin'] }}
      - endpoints.oslo_messaging.auth.neutron.username=neutron
      - endpoints.oslo_messaging.auth.neutron.password={{ pillar['osh']['neutron_users']['neutron'] }}
      - endpoints.identity.auth.admin.password={{ pillar['osh']['osh_users']['admin'] }}
      - endpoints.identity.auth.neutron.username=neutron
      - endpoints.identity.auth.neutron.password={{ pillar['osh']['neutron_users']['neutron'] }}
      - endpoints.identity.auth.nova.username=neutron_nova
      - endpoints.identity.auth.nova.password={{ pillar['osh']['neutron_users']['neutron_nova'] }}
      - endpoints.identity.auth.placement.username=neutron_placement
      - endpoints.identity.auth.placement.password={{ pillar['osh']['neutron_users']['neutron_placement'] }}
      - endpoints.identity.auth.designate.username=neutron_designate
      - endpoints.identity.auth.designate.password={{ pillar['osh']['neutron_users']['neutron_designate'] }}
      - endpoints.identity.auth.ironic.username=neutron_ironic
      - endpoints.identity.auth.ironic.password={{ pillar['osh']['neutron_users']['neutron_ironic'] }}
      - endpoints.identity.auth.test.username=neutron_test
      - endpoints.identity.auth.test.password={{ pillar['osh']['neutron_users']['neutron_test'] }}
    - require:
      - k8s: neutron_httproute
