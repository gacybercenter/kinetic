include:
  - /formulas/common/k8s-efk/yaml-secrets

efk_namespace:
  k8s.namespace_present:
    - namespace: {{ pillar['efk_namespace'] }}

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
    - wait_timeout: {{ pillar.get('opensearch_operator_wait_timeout', 300) }}
    - wait_interval: 15
    - keep_values_file: True
    - require:
      - k8s: efk_namespace
      - k8s_helm: opensearch_operator_repo

opensearch_cluster_cr:
  k8s.opensearch_cluster_present:
    - namespace: {{ pillar.get('efk_namespace', 'efk') }}
    - cluster_name: opensearch
    - spec: {{ pillar.get('res-k8s:efk:cluster:spec', {}) }}
    - require:
      - k8s_helm: opensearch_operator_repo
      - k8s: opensearch_security_config
      - k8s: opensearch_tls_certificate

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



opensearch_api_httproute:
  k8s.httproute_present:
    - name: opensearch-api-route
    - namespace: {{ pillar.get('efk_namespace', 'efk') }}
    - parent_refs:
        - name: traefik-internal
          namespace: ingress
          sectionName: websecure
    - hostnames:
        - api.logger.services.gacyberrange.org
    - rules:
        - matches:
            - path:
                type: PathPrefix
                value: "/"
          backendRefs:
            - name: opensearch-cluster-master
              port: 9200
    - require:
      - k8s: opensearch_cluster_cr


efk_backend_tls:
  k8s.backendtlspolicy_present:
    - name: efk-backend-tls
    - namespace: efk
    - target_refs:
      - kind: Service
        name: opensearch-cluster-master
    - hostname: api.logger.services.gacyberrange.org
    - ca_certificate_refs:
      - kind: Secret
        name: opensearch-tls-secret
    - require:
      - k8s: opensearch_cluster_cr
      - k8s: opensearch_tls_certificate

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
