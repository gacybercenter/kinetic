# Add a step to uninstall OpenSearch Dashboards Helm release if it exists to handle selector conflict.

efk_namespace:
  k8s.namespace_present:
    - namespace: {{ pillar['efk_namespace'] }}

opensearch_security_config_secret:
  k8s.secret_present:
    - name: {{ pillar['opensearch-security-config']['name'] }}
    - namespace: {{ pillar.get('efk_namespace', 'efk') }}
    - type: {{ pillar['opensearch-security-config']['type'] }}
    - data: {{ pillar['opensearch-security-config']['data'] | tojson }}
    - require:
      - k8s: efk_namespace

opensearch_tls_certificate:
  k8s.certmanager_certificate_present:
    - name: opensearch-tls
    - namespace: {{ pillar.get('efk_namespace', 'efk') }}
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
    - version: {{ pillar.get('opensearch_version', '2.12.0') }}
    - pillar_key: opensearch_helm
    - wait_timeout: 300
    - require:
      - k8s: efk_namespace
      - k8s_helm: opensearch_repo
      - k8s: opensearch_security_config_secret
      - k8s: opensearch_tls_certificate

# Create ConfigMap for OpenSearch Dashboards configuration
opensearch_dashboards_configmap:
  k8s.configmap_present:
    - namespace: {{ pillar.get('efk_namespace', 'efk') }}
    - configmap_name: opensearch-dashboards-config
    - data:
        opensearch_dashboards.yml: |
          # OpenSearch connection configuration
          opensearch.hosts: ["https://{{ pillar.get('opensearch_service_host', 'opensearch-cluster-master') }}.{{ pillar.get('efk_namespace', 'efk') }}.svc.cluster.local:{{ pillar.get('opensearch_service_port', 9200) }}"]
          opensearch.username: "admin"
          opensearch.password: "{{ pillar.get('opensearch_admin_password', 'YourStrongPassword123!') }}"
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
  cmd.run:
    - name: |
        helm upgrade --install opensearch-dashboards opensearch/opensearch-dashboards \
          --version {{ pillar.get('opensearch_dashboards_version', '2.12.0') }} \
          --namespace {{ pillar.get('efk_namespace', 'efk') }} \
          --set replicas={{ pillar.get('opensearch_dashboards_replicas', 1) }} \
          --set image.repository=opensearchproject/opensearch-dashboards \
          --set image.tag={{ pillar.get('opensearch_dashboards_tag', '3.2.0') }} \
          --set image.pullPolicy=IfNotPresent \
          --set service.type={{ pillar.get('opensearch_dashboards_service_type', 'ClusterIP') }} \
          --set service.port={{ pillar.get('opensearch_dashboards_service_port', 5601) }} \
          --set resources.limits.cpu={{ pillar.get('opensearch_dashboards_cpu_limit', '500m') }} \
          --set resources.limits.memory={{ pillar.get('opensearch_dashboards_memory_limit', '512Mi') }} \
          --set resources.requests.cpu={{ pillar.get('opensearch_dashboards_cpu_request', '200m') }} \
          --set resources.requests.memory={{ pillar.get('opensearch_dashboards_memory_request', '256Mi') }} \
          --set ingress.enabled={{ pillar.get('opensearch_dashboards_ingress_enabled', 'true') }} \
          --set ingress.ingressClassName={{ pillar.get('opensearch_dashboards_ingress_class', 'nginx') }} \
          --set ingress.hosts[0].host={{ pillar.get('opensearch_dashboards_ingress_host', 'dashboard.logger.services.gacyberrange.org') }} \
          --set ingress.hosts[0].paths[0].path=/ \
          --set ingress.hosts[0].paths[0].pathType=Prefix \
          --set ingress.hosts[0].paths[0].backend.service.name={{ pillar.get('opensearch_dashboards_service_name', 'opensearch-dashboards') }} \
          --set ingress.hosts[0].paths[0].backend.service.port.number={{ pillar.get('opensearch_dashboards_service_port', 5601) }} \
          --set extraVolumes[0].name=opensearch-dashboards-config \
          --set extraVolumes[0].configMap.name=opensearch-dashboards-config \
          --set extraVolumeMounts[0].name=opensearch-dashboards-config \
          --set extraVolumeMounts[0].mountPath=/usr/share/opensearch-dashboards/config/opensearch_dashboards.yml \
          --set extraVolumeMounts[0].subPath=opensearch_dashboards.yml \
          --set extraVolumeMounts[0].readOnly=true \
          --set extraVolumes[1].name=opensearch-tls-secret \
          --set extraVolumes[1].secret.secretName=opensearch-tls-secret \
          --set extraVolumeMounts[1].name=opensearch-tls-secret \
          --set extraVolumeMounts[1].mountPath=/usr/share/opensearch-dashboards/config/certs \
          --set extraVolumeMounts[1].readOnly=true \
          --set extraEnvs[0].name=OPENSEARCH_DASHBOARDS_DEFAULT_TENANT \
          --set extraEnvs[0].value={{ pillar.get('opensearch_dashboards_default_tenant', 'global_tenant') }} \
          --wait --timeout 300s || echo "Installation failed, check logs for details"

    - require:
      - k8s: efk_namespace
      - helm: opensearch_repo
      - helm: opensearch_helm_install
