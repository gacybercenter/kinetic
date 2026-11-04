include:
  - /formulas/horizon/install
  - /formulas/osh-helm-repos/configure

{# hosts may be plain names, or dicts with a 'host' key (the old Ingress
   shape). Normalize either way.
     osh:horizon:ingress:hosts: [horizon.example.org]
#}
{% set horizon_hostnames = [] %}
{% for h in pillar['osh']['horizon']['ingress']['hosts'] %}
{% if h is mapping %}
{% do horizon_hostnames.append(h['host']) %}
{% else %}
{% do horizon_hostnames.append(h) %}
{% endif %}
{% endfor %}

# TLS terminates on the external Gateway. The chart Service is named from
# endpoints.dashboard.hosts.default (horizon-int) and listens on port 80.
horizon_httproute:
  k8s.httproute_present:
    - name: horizon-route
    - namespace: openstack
    - parent_refs:
        - name: traefik-external
          namespace: ingress
          sectionName: websecure-ext
    - hostnames: {{ horizon_hostnames | tojson }}
    - rules:
        - matches:
            - path:
                type: PathPrefix
                value: "/"
          backendRefs:
            - name: horizon-int
              port: 80

install_horizon:
  k8s_helm.helm_release_present:
    - release_name: horizon
    - chart_name: openstack-helm/horizon
    - namespace: openstack
    - wait_timeout: 300
    - wait_interval: 10
    - keep_values_file: true
    - pillar_key: osh:horizon:values
    - set_values:
      - endpoints.oslo_db.auth.admin.username=root
      - endpoints.oslo_db.auth.admin.password={{ pillar['osh']['mariadb_admin'] }}
      - endpoints.oslo_db.auth.horizon.username=horizon
      - endpoints.oslo_db.auth.horizon.password={{ pillar['osh']['horizon']['users']['horizon'] }}
      - endpoints.identity.auth.admin.password={{ pillar['osh']['osh_users']['admin'] }}
      - conf.horizon.local_settings.config.horizon_secret_key={{ pillar['osh']['horizon']['secret_key'] }}
    - require:
      - k8s: horizon_httproute

cleanup_completed_jobs:
  k8s.job_cleanup:
    - namespace: openstack
    - require:
      - k8s_helm: install_horizon
