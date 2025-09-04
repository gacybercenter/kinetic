# Install MetalLB for LoadBalancer IP management with a specified IP pool (10.150.1.43 - 10.150.1.50)
# and deploy NGINX Ingress Controller with MetalLB annotations to request an IP from the pool.

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

# Create namespace for MetalLB
metallb_namespace:
  k8s.namespace_present:
    - namespace: {{ pillar.get('metallb_namespace', 'metallb-system') }}
    - require:
      - test: helm_installed

# Add the MetalLB Helm repository
add_metallb_repo:
  cmd.run:
    - name: helm repo add metallb https://metallb.github.io/metallb
    - unless: helm repo list | grep -q "metallb"
    - require:
      - test: helm_installed

# Update Helm repositories to ensure the latest charts are available
update_helm_repos:
  cmd.run:
    - name: helm repo update
    - require:
      - cmd: add_metallb_repo

# Render MetalLB values file with IP pool configuration
render_metallb_values:
  file.managed:
    - name: /tmp/metallb-values.yaml
    - contents: |
        configInline:
          address-pools:
          - name: {{ pillar.get('nginx_ingress_metallb_pool', 'default') }}
            protocol: layer2
            addresses:
            - {{ pillar.get('metallb_ip_range_start', '10.150.1.43') }}-{{ pillar.get('metallb_ip_range_end', '10.150.1.50') }}
    - makedirs: True
    - require:
      - test: helm_installed

# Install or upgrade MetalLB using Helm
install_metallb:
  cmd.run:
    - name: |
        helm upgrade --install metallb metallb/metallb \
          --namespace {{ pillar.get('metallb_namespace', 'metallb-system') }} \
          --create-namespace \
          --values /tmp/metallb-values.yaml \
          --wait
    - require:
      - k8s: metallb_namespace
      - cmd: update_helm_repos
      - file: render_metallb_values
    - unless: kubectl get deployment -n {{ pillar.get('metallb_namespace', 'metallb-system') }} | grep -q "metallb-controller"

# Add the NGINX Ingress Controller Helm repository
add_nginx_ingress_repo:
  cmd.run:
    - name: helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    - unless: helm repo list | grep -q "ingress-nginx"
    - require:
      - test: helm_installed

# Install or upgrade NGINX Ingress Controller using Helm with MetalLB annotations
install_nginx_ingress_controller:
  cmd.run:
    - name: |
        helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
          --namespace {{ pillar.get('nginx_ingress_namespace', 'openstack') }} \
          --create-namespace \
          --set controller.service.type={{ pillar.get('nginx_ingress_service_type', 'LoadBalancer') }} \
          --set controller.replicaCount={{ pillar.get('nginx_ingress_replica_count', 2) }} \
          --set controller.watchIngressWithoutClass=true \
          --set controller.deployment.progressDeadlineSeconds={{ pillar.get('nginx_ingress_progress_deadline_seconds', 20) }} \
          --set controller.service.annotations."metallb\.universe\.tf/address-pool"={{ pillar.get('nginx_ingress_metallb_pool', 'default') }} 
    - require:
      - cmd: update_helm_repos
      - test: certmanager_installed
      - cmd: install_metallb
    - unless: kubectl get deployment -n {{ pillar.get('nginx_ingress_namespace', 'openstack') }} | grep -q "ingress-nginx-controller"