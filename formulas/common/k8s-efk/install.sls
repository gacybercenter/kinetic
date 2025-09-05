# Add a step to restart OpenSearch pods after applying security config to ensure changes are loaded.

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
    - version: {{ pillar.get('opensearch_version', '3.2.0') }}
    - namespace: {{ pillar.get('efk_namespace', 'efk') }}
    - values: /tmp/opensearch-values.yaml
    - require:
      - k8s: efk_namespace
      - helm: opensearch_repo
      - cmd: apply_opensearch_security_config
      - cmd: restart_opensearch_pods
      - cmd: apply_opensearch_tls_cert
      - file: render_opensearch_values

render_opensearch_dashboards_values:
  file.managed:
    - name: /tmp/opensearch-dashboards-values.yaml
    - source: salt://formulas/common/k8s-efk/files/opensearch-dashboards-values.j2
    - template: jinja
    - makedirs: True

opensearch_dashboards_helm_install:
  helm.release_present:
    - name: opensearch-dashboards
    - chart: opensearch/opensearch-dashboards
    - version: {{ pillar.get('opensearch_dashboards_version', '3.2.0') }}
    - namespace: {{ pillar.get('efk_namespace', 'efk') }}
    - values: /tmp/opensearch-dashboards-values.yaml
    - require:
      - k8s: efk_namespace
      - helm: opensearch_repo
      - helm: opensearch_helm_install
      - file: render_opensearch_dashboards_values