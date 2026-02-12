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
                hash: {{ pillar['opensearch_admin_hash'] }}"
                reserved: true
                backend_roles:
                    - "admin"
                    - "all_access"
                description: "Admin user"
            fluentbit:
                hash: "{{ pillar['opensearch_fluentbit_hash'] }}"
                reserved: false
                backend_roles:
                    - "log_writer"
                description: "Fluent Bit log writer"
            dashboard_user:
                hash: "{{ pillar['opensearch_dashboard_user_hash'] }}"
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
                authc:
                  basic_internal_auth_domain:
                    description: "Authenticate via HTTP Basic against internal users database"
                    http_enabled: true
                    transport_enabled: true
                    order: 0
                    http_authenticator:
                      type: basic
                      challenge: true
                    authentication_backend:
                      type: internal
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
            dashboard_reader:
                reserved: false
                users:
                - "dashboard_user"
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
            - "*"  # Grant all cluster-level permissions
            index_permissions:
            - index_patterns:
                - "*"  # Apply to all indices
                allowed_actions:
                - "*"  # Grant all index-level actions
                - "indices:data/write/index*"
                - "indices:data/write/update*"  # Explicitly include index creation
                - "indices:data/write/bulk*"  # Explicitly include bulk write
                - "indices:admin/create"  # Explicitly include create action
                - "indices:admin/mapping/put"  # Explicitly include mapping updates
                tenant_permissions:
                - tenant_patterns:
                - "*"  # Apply to all tenants
                  allowed_actions:
                  - "*"  # Grant all tenant-level actions
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
