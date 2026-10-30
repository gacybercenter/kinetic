include:
  - /formulas/nova/install
  - /formulas/osh-helm-repos/configure

{# nova_ingress.hosts may be a list of plain hostname strings, or a list of
   dicts with a 'host' key (the shape historically used alongside 'tls' for
   the old Ingress resource) - normalize to a flat list of hostnames either
   way. #}
{% set nova_hostnames = [] %}
{% for h in pillar['osh']['nova_ingress']['hosts'] %}
{% if h is mapping %}
{% do nova_hostnames.append(h['host']) %}
{% else %}
{% do nova_hostnames.append(h) %}
{% endif %}
{% endfor %}

{# console_ingress.hosts may be a list of plain hostname strings, or a list
   of dicts with a 'host' key - normalize to a flat list of hostnames
   either way. #}
{% set console_hostnames = [] %}
{% for h in pillar['osh']['console_ingress']['hosts'] %}
{% if h is mapping %}
{% do console_hostnames.append(h['host']) %}
{% else %}
{% do console_hostnames.append(h) %}
{% endif %}
{% endfor %}

# Routes external Nova (compute) API traffic through the external Gateway
# (traefik-external, websecure-ext listener). TLS termination happens at
# the Gateway listener - the certificate itself is managed elsewhere, not
# here.
nova_httproute:
  k8s.httproute_present:
    - name: nova-route
    - namespace: openstack
    - parent_refs:
        - name: traefik-external
          namespace: ingress
          sectionName: websecure-ext
    - hostnames: {{ nova_hostnames | tojson }}
    - rules:
        - matches:
            - path:
                type: PathPrefix
                value: "/"
          backendRefs:
            - name: nova-api
              port: 8774

# Routes SPICE console traffic (browser-based instance console access)
# through the internal Gateway (traefik-internal, websecure listener) -
# console access is only needed from inside the network, not externally.
console_httproute:
  k8s.httproute_present:
    - name: console-route
    - namespace: openstack
    - parent_refs:
        - name: traefik-internal
          namespace: ingress
          sectionName: websecure
    - hostnames: {{ console_hostnames | tojson }}
    - rules:
        - matches:
            - path:
                type: PathPrefix
                value: "/"
          backendRefs:
            - name: nova-spiceproxy
              port: 6082

install_nova:
  k8s_helm.helm_release_present:
    - release_name: nova
    - chart_name: openstack-helm/nova
    - namespace: openstack
    - wait: False
    - wait_timeout: 300
    - wait_interval: 10
    - keep_values_file: true
    - pillar_key: osh:nova:values
    - set_values:
      - endpoints.oslo_db.auth.admin.username=root
      - endpoints.oslo_db.auth.admin.password={{ pillar['osh']['mariadb_admin'] }}
      - endpoints.oslo_db.auth.nova.username=nova
      - endpoints.oslo_db.auth.nova.password={{ pillar['osh']['nova_users']['nova'] }}
      - endpoints.oslo_db_cell0.auth.admin.username=root
      - endpoints.oslo_db_cell0.auth.admin.password={{ pillar['osh']['mariadb_admin'] }}
      - endpoints.oslo_db_cell0.auth.nova.username=nova
      - endpoints.oslo_db_cell0.auth.nova.password={{ pillar['osh']['nova_users']['nova'] }}
      - endpoints.oslo_db_cell1.auth.admin.username=root
      - endpoints.oslo_db_cell1.auth.admin.password={{ pillar['osh']['mariadb_admin'] }}
      - endpoints.oslo_db_cell1.auth.nova.username=nova
      - endpoints.oslo_db_cell1.auth.nova.password={{ pillar['osh']['nova_users']['nova'] }}
      - endpoints.oslo_messaging.auth.admin.username=rabbitmq
      - endpoints.oslo_messaging.auth.admin.password={{ pillar['osh']['rabbitmq_admin'] }}
      - endpoints.oslo_messaging.auth.nova.username=nova
      - endpoints.oslo_messaging.auth.nova.password={{ pillar['osh']['nova_users']['nova'] }}
      - endpoints.identity.auth.admin.password={{ pillar['osh']['osh_users']['admin'] }}
      - endpoints.identity.auth.nova.username=nova
      - endpoints.identity.auth.nova.password={{ pillar['osh']['nova_users']['nova'] }}
      - endpoints.identity.auth.service.username=nova_service_user
      - endpoints.identity.auth.service.password={{ pillar['osh']['nova_users']['nova_service_user'] }}
      - endpoints.identity.auth.neutron.username=nova_neutron
      - endpoints.identity.auth.neutron.password={{ pillar['osh']['nova_users']['nova_neutron'] }}
      - endpoints.identity.auth.ironic.username=nova_ironic
      - endpoints.identity.auth.ironic.password={{ pillar['osh']['nova_users']['nova_ironic'] }}
      - endpoints.identity.auth.placement.username=nova_placement
      - endpoints.identity.auth.placement.password={{ pillar['osh']['nova_users']['nova_placement'] }}
      - endpoints.identity.auth.cinder.username=nova_cinder
      - endpoints.identity.auth.cinder.password={{ pillar['osh']['nova_users']['nova_cinder'] }}
      - endpoints.identity.auth.test.username=nova-test
      - endpoints.identity.auth.test.password={{ pillar['osh']['nova_users']['nova-test'] }}
      - conf.ceph.cinder.secret_uuid={{ pillar['osh']['libvirt_ceph_secret'] }}
      - conf.nova.libvirt.rbd_secret_uuid={{ pillar['osh']['libvirt_ceph_secret'] }}
    - require:
      - k8s: nova_httproute
      - k8s: console_httproute
