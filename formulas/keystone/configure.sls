include:
  - /formulas/keystone/install
  - /formulas/osh-helm-repos/configure

keystone_httproute:
  k8s.httproute_present:
    - name: keystone-route
    - namespace: openstack
    - parent_refs:
        - name: traefik-internal
          namespace: ingress
          sectionName: websecure
    - hostnames: {{ pillar['osh']['keystone_ingress']['hosts'] | map(attribute='host') | list }}
    - rules:
        - matches:
            - path:
                type: PathPrefix
                value: "/"
          backendRefs:
            - name: keystone-api
              port: 5000
# conf.keystone.wsgi_keystone is a large multi-line Apache config, which
# cannot be passed via set_values (Helm --set only supports flat
# key=value strings, not multi-line block content). Render it as a proper
# Helm values file instead and pass it via values_files (--values).
keystone_wsgi_values_file:
  file.managed:
    - name: /tmp/keystone-wsgi-values.yaml
    - source: salt://formulas/keystone/files/keystone-wsgi-values.yaml.j2
    - template: jinja
    - mode: '0600'
    - user: root
    - group: root

install_keystone:
  k8s_helm.helm_release_present:
    - release_name: keystone
    - chart_name: openstack-helm/keystone
    - namespace: openstack
    - wait_timeout: 300
    - wait_interval: 10
    - keep_values_file: false
    - pillar_key: osh:keystone
    - set_values:
      - endpoints.oslo_db.auth.admin.username=root
      - endpoints.oslo_db.auth.admin.password={{ pillar['osh']['mariadb_admin'] }}
      - endpoints.oslo_db.auth.keystone.username=keystone
      - endpoints.oslo_db.auth.keystone.password={{ pillar['osh']['keystone_admin'] }}
      - endpoints.oslo_messaging.auth.admin.username=rabbitmq
      - endpoints.oslo_messaging.auth.admin.password={{ pillar['osh']['rabbitmq_admin'] }}
      - endpoints.oslo_messaging.auth.keystone.username=keystone
      - endpoints.oslo_messaging.auth.keystone.password={{ pillar['osh']['keystone-rq-user'] }}
      - endpoints.identity.auth.admin.password={{ pillar['osh']['osh_users']['admin'] }}
      - endpoints.identity.auth.test.password={{ pillar['osh']['osh_users']['test'] }}
      - conf.ks_domains.ldap.ldap.password={{ pillar['ldap']['admin-user']['password'] }}
    - values_files:
      - /tmp/keystone-wsgi-values.yaml
    - require:
      - k8s: keystone_httproute
      - file: keystone_wsgi_values_file

# The values file contains secrets (OIDC client secret, crypto passphrase)
# in plaintext - remove it immediately after Helm has consumed it.
keystone_wsgi_values_file_cleanup:
  file.absent:
    - name: /tmp/keystone-wsgi-values.yaml
    - require:
      - k8s_helm: install_keystone
