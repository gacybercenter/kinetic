include:
  - /formulas/common/k8s-efk/install

{% set opensearch_admin_password = salt['kinetic_k8s.get_secret_value'](pillar.get('efk_namespace', 'efk'), 'opensearch-admin-password', 'password', pillar.get('opensearch_admin_password', '')) %}

# Secret for the fluentbit user's password (CRD-managed OpensearchUser)
fluentbit_user_password_secret:
  k8s.secret_present:
    - namespace: {{ pillar.get('efk_namespace', 'efk') }}
    - secret_name: opensearch-fluentbit-password
    - data:
        password: {{ pillar['opensearch_fluentbit_password'] }}
    - require:
      - k8s: efk_namespace

# Declarative OpensearchUser CR for the fluentbit user
fluentbit_user_cr:
  k8s.opensearch_user_present:
    - namespace: {{ pillar.get('efk_namespace', 'efk') }}
    - user_name: fluentbit
    - cluster_name: opensearch
    - password_secret_name: opensearch-fluentbit-password
    - password_key: password
    - require:
      - k8s: fluentbit_user_password_secret

# Create or update the log-writer OpensearchRole CR with permissions for index creation and writing
# Note: role_name becomes the Kubernetes object name (metadata.name) for the
# OpensearchRole/OpensearchUserRoleBinding CRs, so it must be a valid DNS-1123
# name (lowercase alphanumeric and "-" only - no underscores).
update_ldap_log_writer_role:
  opensearch.role_present:
    - name: update_ldap_log_writer_role
    - role_name: log-ldap-writer
    - index_name: openldap-audit-logs-  # Matches openldap-audit-logs-* pattern in kinetic-os.create_role
    - namespace: {{ pillar.get('efk_namespace', 'efk') }}
    - cluster_name: opensearch
    - require:
      - k8s: fluentbit_user_cr
# Map the fluentbit user to the log-ldap-writer role for write access (OpensearchUserRoleBinding CR)
map_fluentbit_user_to_log_writer:
  opensearch.user_role_mapping_present:
    - name: map_fluentbit_user_to_log_writer_role
    - role_name: log-ldap-writer
    - user_name: fluentbit
    - namespace: {{ pillar.get('efk_namespace', 'efk') }}
    - cluster_name: opensearch
    - require:
      - opensearch: update_ldap_log_writer_role

# Create or ensure an OpensearchRole CR with permissions for the audit log indices
create_fluentbit_audit_role:
  opensearch.role_present:
    - name: create_fluentbit_audit_logs_role
    - role_name: audit-logs
    - index_name: openldap-audit-logs-*
    - namespace: {{ pillar.get('efk_namespace', 'efk') }}
    - cluster_name: opensearch
    - require:
      - k8s: fluentbit_user_cr
create_fluentbit_kc_role:
  opensearch.role_present:
    - name: create_fluentbit_kc_role
    - role_name: log-kc-writer
    - index_name: keycloak-logs-*
    - namespace: {{ pillar.get('efk_namespace', 'efk') }}
    - cluster_name: opensearch
    - require:
      - k8s: fluentbit_user_cr


# Map the Fluent Bit user to the audit logs role for write access (OpensearchUserRoleBinding CR)
map_fluentbit_user_to_audit_role:
  opensearch.user_role_mapping_present:
    - name: map_fluentbit_user_to_audit_logs_role
    - role_name: audit-logs
    - user_name: {{ pillar.get('opensearch_user_name', 'fluentbit') }}
    - namespace: {{ pillar.get('efk_namespace', 'efk') }}
    - cluster_name: opensearch
    - require:
      - opensearch: create_fluentbit_audit_role
      
map_fluentbit_user_to_kc_role:
  opensearch.user_role_mapping_present:
    - name: map_fluentbit_user_to_kc_role
    - role_name: log-kc-writer
    - user_name: {{ pillar.get('opensearch_user_name', 'fluentbit') }}
    - namespace: {{ pillar.get('efk_namespace', 'efk') }}
    - cluster_name: opensearch
    - require:
      - opensearch: create_fluentbit_kc_role
