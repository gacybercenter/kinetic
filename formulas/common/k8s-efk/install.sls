include:
  - /formulas/common/k8s-efk/yaml-secrets

efk_namespace:
  k8s.namespace_present:
    - namespace: {{ pillar['efk_namespace'] }}

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

opensearch_repo:
  k8s_helm.helm_repo_present:
    - repo_name: opensearch
    - repo_url: https://opensearch-project.github.io/helm-charts/
    - update_cache: True

opensearch_helm_install:
  k8s_helm.helm_release_present:
    - release_name: opensearch
    - chart_name: opensearch/opensearch
    - namespace: {{ pillar.get('efk_namespace', 'efk') }}
    - version: {{ pillar.get('opensearch_version') }}
    - pillar_key: opensearch_helm
    - keep_values_file: True
    - wait_timeout: 300
    - require:
      - k8s: efk_namespace
      - k8s_helm: opensearch_repo
      - k8s: opensearch_tls_certificate

# Create an HTTPRoute for the OpenSearch API (Gateway API), attached to the
# shared traefik-internal Gateway managed by k8s-ingress-controller.
#
# Note: unlike Ingress, Gateway API terminates TLS at the Gateway's listener,
# not per-HTTPRoute - so the opensearch-tls-secret cert generated above is
# not referenced here. TLS for this hostname is served by whatever
# certificateRefs are configured on the traefik-internal Gateway's
# "websecure" listener (see formulas/common/k8s-ingress-controller). If
# api.logger.services.gacyberrange.org needs its own dedicated certificate
# rather than the shared internal cert, a listener for that hostname (using
# opensearch-tls-secret) needs to be added to that Gateway.
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
      - k8s_helm: opensearch_helm_install

# Create ConfigMap for OpenSearch Dashboards configuration
opensearch_dashboards_configmap:
  k8s.configmap_present:
    - namespace: {{ pillar.get('efk_namespace', 'efk') }}
    - configmap_name: opensearch-dashboards-config
    - data:
        opensearch_dashboards.yml: |
          # OpenSearch connection configuration
          opensearch.hosts: ["https://{{ pillar.get('opensearch_service_host') }}:9200"]
          opensearch.username: "admin"
          opensearch.password: "{{ pillar.get('opensearch_admin_password') }}"
          opensearch.ssl.verificationMode: {{ pillar.get('opensearch_ssl_verification_mode', 'none') }}
          opensearch.ssl.certificateAuthorities: ["/usr/share/opensearch-dashboards/config/certs/ca.crt"]
          logging.verbose: true
    - labels:
        app: opensearch-dashboards
    - annotations:
        description: Configuration for OpenSearch Dashboards
    - require:
      - k8s: efk_namespace

# Install OpenSearch Dashboards in the same namespace as OpenSearch using --set options
opensearch_dashboards_helm_install:
  k8s_helm.helm_release_present:
    - release_name: opensearch-dashboards
    - chart_name: opensearch/opensearch-dashboards
    - namespace: {{ pillar.get('efk_namespace', 'efk') }}
    - version: {{ pillar.get('opensearch_dashboards_version', '3.5.0') }}
    - pillar_key: opensearch_dashboards_helm_values
    - wait_timeout: 300
    - keep_values_file: True
    - require:
      - k8s: efk_namespace
      - k8s_helm: opensearch_repo
      - k8s_helm: opensearch_helm_install
