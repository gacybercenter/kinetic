opensearch_security_config:
  k8s.secret_present:
    - name: opensearchSecurityConfig
    - secret_name: opensearch-security-config
    - namespace: {{ pillar.get('efk_namespace', 'efk') }}
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
            kibana_server:
                reserved: true
                users:
                - "kibanaserver"
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
            admin_action_group:
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
        tenants.yml: |
            _meta:
                type: "tenants"
                config_version: 2
