efk_namespace:
  k8s.namespace_present:
    - namespace: {{ pillar['efk_namespace'] }}

# --- OpenSearch Kubernetes Operator ---
# https://github.com/opensearch-project/opensearch-k8s-operator/blob/main/charts/opensearch-operator/values.yaml
# Installs the operator and its CRDs (OpenSearchCluster, OpenSearchISMPolicy,
# OpenSearchActionGroup, etc). This is independent of the opensearch/opensearch
# Helm chart installed later in this file - the two are alternative ways to
# run OpenSearch and are not wired together here. Override chart values via
# pillar under res-k8s:opensearch-operator:helm_values (e.g.
# manager.watchNamespace, useRoleBindings, legacyAPI.enabled).
opensearch_operator_repo:
  k8s_helm.helm_repo_present:
    - repo_name: opensearch-operator
    - repo_url: https://opensearch-project.github.io/opensearch-k8s-operator/
    - update_cache: True

opensearch_operator_install:
  k8s_helm.helm_release_present:
    - release_name: opensearch-operator
    - chart_name: opensearch-operator/opensearch-operator
    - namespace: {{ pillar.get('efk_namespace', 'efk') }}
{%- if pillar.get('opensearch_operator_version') is not none %}
    - version: {{ pillar.get('opensearch_operator_version') }}
{%- endif %}
    - pillar_key: res-k8s:efk:operator:helm_values
    - wait_timeout: {{ pillar.get('opensearch_operator_wait_timeout', 900) }}
    - wait_interval: 15
    - keep_values_file: True
    - require:
      - k8s: efk_namespace
      - k8s_helm: opensearch_operator_repo

opensearch_tls_certificate:
  k8s.certmanager_certificate_present:
    - name: opensearch-tls
    - namespace: {{ pillar.get('efk_namespace', 'efk') }}
    - certificate_name: opensearch-tls-secret
    - secret_name: opensearch-tls-secret
    - issuer_name: cyberrange-ca-issuer
    - issuer_kind: ClusterIssuer
    - common_name: {{ pillar.get('opensearch_service_host') }}.{{ pillar.get('efk_namespace') }}.svc.cluster.local
    - dns_names:
        - {{ pillar.get('opensearch_service_host') }}
        - {{ pillar.get('opensearch_service_host') }}-headless
        - {{ pillar.get('opensearch_service_host') }}.{{ pillar.get('efk_namespace') }}.svc.cluster.local:{{ pillar.get('opensearch_service_port', 9200) }}
        - api.logger.services.gacyberrange.org
        - dashboard.logger.services.gacyberrange.org
    - duration: 2160h
    - renew_before: 360h
    - require:
      - k8s: efk_namespace

# Admin client certificate for securityadmin.sh (OpenSearch security plugin)
opensearch_admin_certificate:
  k8s.certmanager_certificate_present:
    - name: opensearch-admin
    - namespace: {{ pillar.get('efk_namespace', 'efk') }}
    - certificate_name: opensearch-admin
    - secret_name: opensearch-admin-tls
    - issuer_name: cyberrange-ca-issuer
    - issuer_kind: ClusterIssuer
    - common_name: opensearch-admin
    - subject:
        organizations:
          - gacyberrange
        organizationalUnits:
          - opensearch
        countries:
          - US
    - duration: 8760h
    - renew_before: 720h
    - private_key:
        algorithm: RSA
        size: 2048
        encoding: PKCS8
    - usages:
        - client auth
        - digital signature
        - key encipherment
    - require:
      - k8s: efk_namespace

opensearch_internal_users:
  k8s.secret_present:
    - name: internalUsersSecret
    - secret_name: internal-users-secret
    - namespace: {{ pillar.get('efk_namespace', 'efk') }}
    - data:
        internal_users.yml: |
            # This is the internal user database
            # The hash value is a bcrypt hash and can be generated with plugin/tools/hash.sh
            _meta:
                type: "internalusers"
                config_version: 2
            admin:
                hash: {{ pillar['opensearch_admin_hash'] }}
                reserved: true
                backend_roles:
                    - "admin"
                    - "all_access"
                description: "Admin user"
            fluentbit:
                hash: {{ pillar['opensearch_fluentbit_hash'] }}
                reserved: false
                backend_roles:
                    - "log_writer"
                description: "Fluent Bit log writer"
            dashboard_user:
                hash: {{ pillar['opensearch_dashboard_user_hash'] }}
                reserved: false
                backend_roles:
                    - "dashboard_reader"
                description: "OpenSearch Dashboards read-only user"

opensearch_action_groups_secret:
  k8s.secret_present:
    - name: actionGroupsSecret
    - secret_name: action-groups-secret
    - namespace: {{ pillar['efk_namespace'] }}
    - data:
        action_groups.yml: |
            # This defines reusable action groups for permissions
            gcr_action_group:
                reserved: false
                hidden: false
                allowed_actions:
                - "indices:data/write/index*"
                - "indices:data/write/update*"
                - "indices:admin/mapping/put"
                - "indices:data/write/bulk*"
                - "read"
                - "write"
                static: false
            admin_action_group:  # Optional: Add for future admin-related roles if needed
                reserved: false
                hidden: false
                allowed_actions:
                - "indices:admin/*"
                - "indices:data/*"
                - "cluster:admin/*"
                static: false
            _meta:
                type: "actiongroups"
                config_version: 2
opensearch_config_secret:
  k8s.secret_present:
    - name: configSecret
    - secret_name: config-secret
    - namespace: {{ pillar['efk_namespace'] }}
    - data:
        config.yml: |
            _meta:
              type: "config"
              config_version: 2
            config:
              dynamic:
                http:
                  anonymous_auth_enabled: false
                authc:
                  basic_internal_auth_domain:
                    description: "Authenticate via HTTP Basic against internal users database"
                    http_enabled: true
                    transport_enabled: true
                    order: 0
                    http_authenticator:
                      type: basic
                      challenge: false
                    authentication_backend:
                      type: internal
                  openid_auth_domain:
                    description: "Authenticate via Keycloak OIDC"
                    http_enabled: true
                    transport_enabled: true
                    order: 1
                    http_authenticator:
                      type: openid
                      challenge: false
                      config:
                        subject_key: preferred_username
                        roles_key: groups
                        openid_connect_url: "https://keycloak.rsc.gacyberrange.org/realms/rsc/.well-known/openid-configuration"
                        jwt_clock_skew_tolerance_seconds: 30
                    authentication_backend:
                      type: noop
opensearch_tenants_secret:
  k8s.secret_present:
    - name: tenantsSecret
    - secret_name: tenants-secret
    - namespace: {{ pillar['efk_namespace'] }}
    - data:
        tenants.yml: |
            _meta:
                type: "tenants"
                config_version: 2
opensearch_roles_mapping_secret:
  k8s.secret_present:
    - name: roleMappingSecret
    - secret_name: role-mapping-secret
    - namespace: {{ pillar['efk_namespace'] }}
    - data:
        roles_mapping.yml: |
            # This maps roles to users and groups
            _meta:
                type: "rolesmapping"
                config_version: 2
            all_access:
                reserved: true
                backend_roles:
                  - "admins"
                users:
                  - "admin"
            admin:
                reserved: true
                users:
                - "admin"
                backend_roles:
                - "all_access"
            log_writer:
                reserved: false
                users:
                - "fluentbit"
            kibana_user:
                reserved: false
                backend_roles:
                  - "admins"
            dashboard_reader:
                reserved: false
                backend_roles:
                  - "admins"
                  - "se_cyber"
                  - "ro"
opensearch_roles_secret:
  k8s.secret_present:
    - name: rolesSecret
    - secret_name: roles-secret
    - namespace: {{ pillar['efk_namespace'] }}
    - data:
        roles.yml: |
            # This defines the access control roles
            _meta:
                type: "roles"
                config_version: 2
            admin:
                reserved: true
                cluster_permissions:
                - "*"
                - "cluster:monitor/health"
                index_permissions:
                - index_patterns:
                    - "*"
                  allowed_actions:
                    - "*"
                    - "indices:data/write/index*"
                    - "indices:data/write/update*"
                    - "indices:data/write/bulk*"
                    - "indices:admin/create"
                    - "indices:admin/mapping/put"
                tenant_permissions:
                - tenant_patterns:
                    - "*"
                  allowed_actions:
                    - "*"
            log_writer:
                reserved: false
                cluster_permissions:
                - "cluster_monitor"
                - "cluster_composite_ops"
                index_permissions:
                - index_patterns:
                    - "*"
                  allowed_actions:
                    - "write"
                    - "create_index"
                    - "manage"
                    - "indices:data/write/index"
                    - "indices:data/write/bulk"
            dashboard_reader:
                reserved: false
                cluster_permissions:
                - "cluster_monitor"
                index_permissions:
                - index_patterns:
                    - "*"
                  allowed_actions:
                    - "read"
                    - "view_index_metadata"
                tenant_permissions:
                - tenant_patterns:
                    - "global_tenant"
                  allowed_actions:
                    - "kibana_all_read"

# opensearch_repo:
#   k8s_helm.helm_repo_present:
#     - repo_name: opensearch
#     - repo_url: https://opensearch-project.github.io/helm-charts/
#     - update_cache: True

# opensearch_helm_install:
#   k8s_helm.helm_release_present:
#     - release_name: opensearch
#     - chart_name: opensearch/opensearch
#     - namespace: {{ pillar.get('efk_namespace', 'efk') }}
#     - version: {{ pillar.get('opensearch_version') }}
#     - pillar_key: opensearch_helm
#     - keep_values_file: True
#     - wait_timeout: 300
#     - require:
#       - k8s: efk_namespace
#       - k8s_helm: opensearch_repo
#       - k8s: opensearch_tls_certificate

# opensearch_api_httproute:
#   k8s.httproute_present:
#     - name: opensearch-api-route
#     - namespace: {{ pillar.get('efk_namespace', 'efk') }}
#     - parent_refs:
#         - name: traefik-internal
#           namespace: ingress
#           sectionName: websecure
#     - hostnames:
#         - api.logger.services.gacyberrange.org
#     - rules:
#         - matches:
#             - path:
#                 type: PathPrefix
#                 value: "/"
#           backendRefs:
#             - name: opensearch-cluster-master
#               port: 9200
#     - require:
#       - k8s_helm: opensearch_helm_install

# efk_backend_tls:
#   k8s.backendtlspolicy_present:
#     - name: efk-backend-tls
#     - namespace: efk
#     - target_refs:
#       - kind: Service
#         name: opensearch-cluster-master
#     - hostname: api.logger.services.gacyberrange.org
#     - ca_certificate_refs:
#       - kind: Secret
#         name: opensearch-tls-secret
#     - require:
#       - k8s_helm: opensearch_helm_install
#       - k8s: opensearch_tls_certificate

# # Create ConfigMap for OpenSearch Dashboards configuration
# opensearch_dashboards_configmap:
#   k8s.configmap_present:
#     - namespace: {{ pillar.get('efk_namespace', 'efk') }}
#     - configmap_name: opensearch-dashboards-config
#     - data:
#         opensearch_dashboards.yml: |
#           # OpenSearch connection configuration
#           opensearch.hosts: ["https://{{ pillar.get('opensearch_service_host') }}:9200"]
#           opensearch.username: "admin"
#           opensearch.password: "{{ pillar.get('opensearch_admin_password') }}"
#           opensearch.ssl.verificationMode: {{ pillar.get('opensearch_ssl_verification_mode', 'none') }}
#           opensearch.ssl.certificateAuthorities: ["/usr/share/opensearch-dashboards/config/certs/ca.crt"]
#           opensearch_security.auth.multiple_auth_enabled: true
#           opensearch_security.auth.type: ["openid", "basicauth"]
#           opensearch_security.openid.connect_url: "https://keycloak.rsc.gacyberrange.org/realms/rsc/.well-known/openid-configuration"
#           opensearch_security.openid.client_id: "opensearch-dashboard"
#           opensearch_security.openid.verify_hostnames: false
#           opensearch_security.openid.refresh_tokens: false
#           opensearch_security.openid.scope: "openid profile email groups"
#           opensearch_security.openid.trust_dynamic_headers: true
#           opensearch.requestHeadersAllowlist: ["Authorization", "securitytenant", "WWW-Authenticate", "security_tenant"]
#           opensearch_security.openid.base_redirect_url: "https://dashboard.logger.services.gacyberrange.org"
#           opensearch_security.openid.client_secret: {{ pillar['ldap']['realms']['rsc']['clients']['opensearch-dashboard']['secret'] }}
#           opensearch_security.openid.logout_url: https://keycloak.rsc.gacyberrange.org/realms/rsc/protocol/openid-connect/logout
#           logging.root.level: debug
#     - labels:
#         app: opensearch-dashboards
#     - annotations:
#         description: Configuration for OpenSearch Dashboards
#     - require:
#       - k8s: efk_namespace

# # Install OpenSearch Dashboards in the same namespace as OpenSearch using --set options
# opensearch_dashboards_helm_install:
#   k8s_helm.helm_release_present:
#     - release_name: opensearch-dashboards
#     - chart_name: opensearch/opensearch-dashboards
#     - namespace: {{ pillar.get('efk_namespace', 'efk') }}
#     - version: {{ pillar.get('opensearch_dashboards_version', '3.5.0') }}
#     - pillar_key: opensearch_dashboards_helm_values
#     - wait_timeout: 300
#     - keep_values_file: True
#     - require:
#       - k8s: efk_namespace
#       - k8s_helm: opensearch_repo
#       - k8s_helm: opensearch_helm_install

# # Create an HTTPRoute for OpenSearch Dashboards (Gateway API), attached to
# # the shared traefik-internal Gateway managed by k8s-ingress-controller.
# # See the note on opensearch_api_httproute above regarding TLS being
# # terminated at the Gateway listener rather than per-HTTPRoute.
# opensearch_dashboards_httproute:
#   k8s.httproute_present:
#     - name: opensearch-dashboards-route
#     - namespace: {{ pillar.get('efk_namespace', 'efk') }}
#     - parent_refs:
#         - name: traefik-internal
#           namespace: ingress
#           sectionName: websecure
#     - hostnames:
#         - dashboard.logger.services.gacyberrange.org
#     - rules:
#         - matches:
#             - path:
#                 type: PathPrefix
#                 value: "/"
#           backendRefs:
#             - name: opensearch-dashboards
#               port: 5601
#     - require:
#       - k8s_helm: opensearch_dashboards_helm_install
