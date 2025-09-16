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
  helm.release_present:
    - name: grafana
    - chart: grafana/grafana
    - version: {{ pillar['k8s-efk']['grafana']['version'] }}
    - namespace: {{ pillar.get('efk_namespace', 'efk') }}
    - set:
        - replicas="{{ pillar.get('k8s-efk.grafana.replicas', 1) }}"
        - image.repository=grafana/grafana
        - image.tag={{ pillar.get('k8s-efk.grafana.version', '10.2.0') }}
        - image.pullPolicy=IfNotPresent
        - grafana\.ini.server.domain={{ pillar.get('k8s-efk.grafana.domain') }}
        - grafana\.ini.server.root_url={{ pillar.get('k8s-efk.grafana.root_url') }}
        - adminUser={{ pillar.get('k8s-efk.grafana.admin_user') }}
        - adminPassword={{ pillar.get('opensearch_admin_password') }}
        - resources.limits.cpu='{{ pillar['k8s-efk']['grafana']['cpu_limit'] }}'
        - resources.limits.memory='{{ pillar['k8s-efk']['grafana']['memory_limit'] }}'
        - resources.requests.cpu='{{ pillar['k8s-efk']['grafana']['cpu_request'] }}'
        - resources.requests.memory='{{ pillar['k8s-efk']['grafana']['memory_request'] }}'
        - ingress.enabled={{ pillar.get('k8s-efk.grafana.ingress_enabled') }}
        - ingress.ingressClassName={{ pillar.get('k8s-efk.grafana.ingress_class') }}
        - ingress.hosts[0]={{ pillar.get('k8s-efk.grafana.ingress_host') }}
        - ingress.path=/
        - ingress.pathType=Prefix
    - require:
      - k8s: efk_namespace
      - cmd: grafana_helm_repo
      - helm: opensearch_helm_install