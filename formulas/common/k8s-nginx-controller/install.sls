# Deploy NGINX Ingress Controller using Helm in the 'openstack' namespace
# and configure it to watch all namespaces for Ingress resources.

include:
  - /formulas/common/helm
  - /formulas/common/k8s-certmanager/install

# Ensure Helm is installed and configured before proceeding
helm_installed:
  test.nop:
    - require:
      - sls: /formulas/common/helm

# Ensure Cert-Manager is installed for TLS support (if needed)
certmanager_installed:
  test.nop:
    - require:
      - sls: /formulas/common/k8s-certmanager/install

# Add the NGINX Ingress Controller Helm repository
add_nginx_ingress_repo:
  cmd.run:
    - name: helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    - unless: helm repo list | grep -q "ingress-nginx"
    - require:
      - test: helm_installed

# Update Helm repositories to ensure the latest charts are available
update_helm_repos:
  cmd.run:
    - name: helm repo update
    - require:
      - cmd: add_nginx_ingress_repo

# Install or upgrade NGINX Ingress Controller using Helm
install_nginx_ingress_controller:
  cmd.run:
    - name: |
        helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
          --namespace {{ pillar.get('nginx_ingress_namespace', 'openstack') }} \
          --create-namespace \
          --set controller.service.type={{ pillar.get('nginx_ingress_service_type', 'LoadBalancer') }} \
          --set controller.replicaCount={{ pillar.get('nginx_ingress_replica_count', 2) }} \
          --set controller.watchIngressWithoutClass=true \
          --wait
    - require:
      - cmd: update_helm_repos
      - test: certmanager_installed
    - unless: kubectl get deployment -n {{ pillar.get('nginx_ingress_namespace', 'openstack') }} | grep -q "ingress-nginx-controller"