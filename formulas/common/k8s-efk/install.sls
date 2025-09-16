# Add a step to uninstall OpenSearch Dashboards Helm release if it exists to handle selector conflict.

efk_namespace:
  k8s.namespace_present:
    - namespace: {{ pillar.get('efk_namespace', 'efk') }}

render_opensearch_security_config:
  file.managed:
    - name: /tmp/opensearch-security-config.yaml
    - source: salt://formulas/common/k8s-efk/files/opensearch-security-config.j2
    - template: jinja
    - makedirs: True

apply_opensearch_security_config:
  cmd.run:
    - name: kubectl apply -f /tmp/opensearch-security-config.yaml
    - require:
      - file: render_opensearch_security_config
    - onchanges:
      - file: render_opensearch_security_config

# Restart OpenSearch pods to ensure security config is reloaded
restart_opensearch_pods:
  cmd.run:
    - name: kubectl delete pod -l app.kubernetes.io/name=opensearch -n {{ pillar.get('efk_namespace', 'efk') }} --grace-period=0 --force || true
    - require:
      - cmd: apply_opensearch_security_config
    - onchanges:
      - cmd: apply_opensearch_security_config

render_opensearch_tls_cert:
  file.managed:
    - name: /tmp/opensearch-tls-cert.yaml
    - source: salt://formulas/common/k8s-efk/files/opensearch-tls-cert.j2
    - template: jinja
    - makedirs: True

apply_opensearch_tls_cert:
  cmd.run:
    - name: kubectl apply -f /tmp/opensearch-tls-cert.yaml
    - require:
      - file: render_opensearch_tls_cert
    - onchanges:
      - file: render_opensearch_tls_cert

opensearch_repo:
  helm.repo_managed:
    - present:
      - name: opensearch
        url: https://opensearch-project.github.io/helm-charts/
    - repo_update: True

render_opensearch_values:
  file.managed:
    - name: /tmp/opensearch-values.yaml
    - source: salt://formulas/common/k8s-efk/files/opensearch-values.j2
    - template: jinja

opensearch_helm_install:
  helm.release_present:
    - name: opensearch
    - chart: opensearch/opensearch
    - version: {{ pillar.get('opensearch_version', '2.12.0') }}
    - namespace: {{ pillar.get('efk_namespace', 'efk') }}
    - values: /tmp/opensearch-values.yaml
    - require:
      - k8s: efk_namespace
      - helm: opensearch_repo
      - cmd: apply_opensearch_security_config
      - cmd: restart_opensearch_pods
      - cmd: apply_opensearch_tls_cert
      - file: render_opensearch_values

# Add Grafana Helm repository
grafana_helm_repo:
  cmd.run:
    - name: helm repo add grafana https://grafana.github.io/helm-charts && helm repo update
    - unless: helm repo list | grep grafana
    - require:
      - k8s: efk_namespace

# Install Grafana in the same namespace as OpenSearch
grafana_helm_install:
  cmd.run:
    - name: |
        helm upgrade --install grafana grafana/grafana \
          --version {{ pillar.get('k8s-efk.grafana.version', 'latest') }} \
          --namespace {{ pillar.get('efk_namespace', 'efk') }} \
          --set replicas={{ pillar.get('k8s-efk.grafana.replicas', 1) }} \
          --set image.repository=grafana/grafana \
          --set image.tag={{ pillar.get('k8s-efk.grafana.version', '10.2.0') }} \
          --set image.pullPolicy=IfNotPresent \
          --set grafana\.ini.server.domain={{ pillar.get('k8s-efk.grafana.domain', 'grafana.logger.services.gacyberrange.org') }} \
          --set grafana\.ini.server.root_url={{ pillar.get('k8s-efk.grafana.root_url', 'https://grafana.logger.services.gacyberrange.org/') }} \
          --set grafana\.ini.security.admin_user={{ pillar.get('k8s-efk.grafana.admin_user', 'admin') }} \
          --set grafana\.ini.security.admin_password={{ pillar.get('k8s-efk.grafana.admin_password', pillar.get('opensearch_admin_password', 'YourStrongPassword123!')) }} \
          --set service.type={{ pillar.get('k8s-efk.grafana.service_type', 'ClusterIP') }} \
          --set service.port={{ pillar.get('k8s-efk.grafana.service_port', 80) }} \
          --set resources.limits.cpu={{ pillar.get('k8s-efk.grafana.cpu_limit', '500m') }} \
          --set resources.limits.memory={{ pillar.get('k8s-efk.grafana.memory_limit', '512Mi') }} \
          --set resources.requests.cpu={{ pillar.get('k8s-efk.grafana.cpu_request', '200m') }} \
          --set resources.requests.memory={{ pillar.get('k8s-efk.grafana.memory_request', '256Mi') }} \
          --set ingress.enabled={{ pillar.get('k8s-efk.grafana.ingress_enabled', 'true') }} \
          --set ingress.ingressClassName={{ pillar.get('k8s-efk.grafana.ingress_class', 'nginx') }} \
          --set ingress.hosts[0]={{ pillar.get('k8s-efk.grafana.ingress_host', 'grafana.logger.services.gacyberrange.org') }} \
          --set ingress.path=/ \
          --set ingress.pathType=Prefix \
          --wait --timeout 300s || echo "Installation failed, check logs for details"
    - require:
      - k8s: efk_namespace
      - cmd: grafana_helm_repo