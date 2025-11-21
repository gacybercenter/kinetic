# Install MetalLB for LoadBalancer IP management with a specified IP pool
# and deploy NGINX Ingress Controller with MetalLB annotations to request an IP from the pool.
# Use k8s_helm state module for Helm operations.

include:
  - /formulas/common/helm/install
  - /formulas/common/k8s-certmanager

# Ensure Helm is installed and configured before proceeding
helm_installed:
  test.nop:
    - require:
      - sls: /formulas/common/helm/install

# Ensure Cert-Manager is installed for TLS support (if needed)
certmanager_installed:
  test.nop:
    - require:
      - sls: /formulas/common/k8s-certmanager/configure

# Add the MetalLB Helm repository
add_metallb_repo:
  k8s_helm.helm_repo_present:
    - repo_name: metallb
    - repo_url: https://metallb.github.io/metallb
    - require:
      - test: helm_installed

# Add the NGINX Ingress Controller Helm repository
add_nginx_ingress_repo:
  k8s_helm.helm_repo_present:
    - repo_name: ingress-nginx
    - repo_url: https://kubernetes.github.io/ingress-nginx
    - require:
      - test: helm_installed

# Update Helm repositories to ensure the latest charts are available
update_helm_repos:
  cmd.run:
    - name: helm repo update
    - require:
      - k8s_helm: add_metallb_repo
      - k8s_helm: add_nginx_ingress_repo

# Install or upgrade MetalLB using Helm via k8s_helm state
install_metallb:
  k8s_helm.helm_release_present:
    - release_name: metallb
    - chart_name: metallb/metallb
    - namespace: {{ pillar.get('metallb_namespace', 'metallb-system') }}
    - wait_timeout: 300
    - wait_interval: 10
    - require:
      - k8s: metallb_namespace
      - cmd: update_helm_repos

# Install or upgrade NGINX Ingress Controller using Helm via k8s_helm state with custom values
install_nginx_ingress_controller:
  k8s_helm.helm_release_present:
    - release_name: ingress-nginx
    - chart_name: ingress-nginx/ingress-nginx
    - namespace: {{ pillar.get('nginx_ingress_namespace', 'openstack') }}
    - values_dict:
        controller:
          service:
            type: {{ pillar.get('nginx_ingress_service_type', 'ClusterIP') }}
          replicaCount: {{ pillar.get('nginx_ingress_replica_count', 2) }}
          watchIngressWithoutClass: true
          progressDeadlineSeconds: {{ pillar.get('nginx_ingress_progress_deadline_seconds', 20) }}
          admissionWebhooks:
            enabled: true
            certManager:
              enabled: {{ pillar.get('nginx_ingress_webhook_certmanager_enabled', true) }}
    - wait_timeout: 300
    - wait_interval: 10
    - require:
      - cmd: update_helm_repos
      - test: certmanager_installed
      - k8s_helm: install_metallb