include:
  - /formulas/keystone/install
  - /formulas/osh-helm-repos/configure

{% set kc = pillar.get('res-k8s', {}).get('keycloak', {}) %}
{% set kc_conn = kc.get('connection', {}) %}
{% set keycloak_addr = kc_conn.get('keycloak_addr', 'k8s://keycloak/keycloak-service:8443') %}
{% set kc_namespace = kc_conn.get('namespace', 'keycloak') %}
{% set kc_secret_name = kc_conn.get('secret_name', 'keycloak-admin') %}
{% set kc_verify = kc_conn.get('verify', False) %}
{% set kc_realm = pillar.get('osh', {}).get('keystone_oidc', {}).get('realm', 'rsc') %}
{% set keystone_oidc = pillar.get('osh', {}).get('keystone_oidc', {}) %}

# Register Keystone as a confidential OIDC client in Keycloak, driven from
# the same osh:keystone_oidc pillar used by the wsgi_keystone Apache config.
keystone_keycloak_client:
  keycloak.client_present:
    - name: keystone
    - realm: {{ kc_realm }}
    - client_id: {{ keystone_oidc.get('client_id', 'keystone') }}
    - client_name: Keystone
    - description: "OpenStack Keystone federation client"
    - enabled: true
    - protocol: openid-connect
    - public_client: false
    - standard_flow_enabled: true
    - direct_access_grants_enabled: false
    - service_accounts_enabled: false
    - redirect_uris:
        - {{ keystone_oidc['redirect_uri'] }}
    - secret: {{ keystone_oidc['client_secret'] | yaml_dquote }}
    - keycloak_addr: {{ keycloak_addr }}
    - namespace: {{ kc_namespace }}
    - secret_name: {{ kc_secret_name }}
    - verify: {{ kc_verify }}

{% for scope_name in keystone_oidc.get('default_client_scopes', []) %}
keystone_keycloak_client_default_scope_{{ scope_name }}:
  keycloak.client_default_scope_present:
    - name: keystone
    - realm: {{ kc_realm }}
    - scope_name: {{ scope_name }}
    - client_id: {{ keystone_oidc.get('client_id', 'keystone') }}
    - keycloak_addr: {{ keycloak_addr }}
    - namespace: {{ kc_namespace }}
    - secret_name: {{ kc_secret_name }}
    - verify: {{ kc_verify }}
    - require:
      - keycloak: keystone_keycloak_client
{% endfor %}

keystone_httproute:
  k8s.httproute_present:
    - name: keystone-route
    - namespace: openstack
    - parent_refs:
        - name: traefik-external
          namespace: ingress
          sectionName: websecure-ext
    - hostnames: {{ pillar['osh']['keystone_ingress']['hosts'] | map(attribute='host') | list }}
    - rules:
        - matches:
            - path:
                type: PathPrefix
                value: "/"
          backendRefs:
            - name: keystone-api
              port: 5000

keystone_federation_configmap:
  k8s.configmap_present:
    - namespace: openstack
    - configmap_name: keystone-federation-conf
    - data:
        99-federation.conf: |
          [auth]
          methods = password,token,openid

          [federation]
          remote_id_attribute = HTTP_OIDC_ISS
          trusted_dashboard=http://localhost:9990/auth/websso/

          [openid]
          remote_id_attribute = HTTP_OIDC_ISS
    - require:
      - k8s: keystone_httproute

keystone_application_credential_configmap:
  k8s.configmap_present:
    - namespace: openstack
    - configmap_name: keystone-application-credential-conf
    - data:
        98-application-credential.conf: |
          [application_credential]
          driver = ttl_sql
          user_limit = 10

          [gcr_application_credential]
          default_ttl_days = 30
          max_ttl_days = 90
          allow_never_expire = false
    - require:
      - k8s: keystone_httproute

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

# The live CA value is read from the trust-manager Bundle's target
# ConfigMap (see install.sls's keystone_ldap_tls_secret) and injected via
# set_values, so it stays in sync with the actual mounted secret content
# instead of using a separate static placeholder. It's wrapped in
# yaml_dquote since it's a multi-line PEM string - embedding raw newlines
# directly into a plain YAML list item would break the block the same way
# the wsgi_keystone content did (see keystone-wsgi-values.yaml.j2).
{% set rsc_cert_ca_bundle = pillar['res-k8s']['rsc-cert-ca'] %}
{% set rsc_ca_value = salt['kinetic_k8s.get_configmap_value']('openstack', rsc_cert_ca_bundle, 'ca.crt', '') %}

install_keystone:
  k8s_helm.helm_release_present:
    - release_name: keystone
    - chart_name: openstack-helm/keystone
    - namespace: openstack
    - wait_timeout: 300
    - wait_interval: 10
    - keep_values_file: true
    - pillar_key: osh:keystone
    - set_values:
      - endpoints.ldap.auth.client.tls.ca= |
        {{ rsc_ca_value | yaml_dquote }}
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
      - conf.ks_domains.rsc.ldap.password={{ pillar['ldap']['admin-user']['password'] }}
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
