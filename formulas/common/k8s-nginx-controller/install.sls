# Install MetalLB for LoadBalancer IP management with a specified IP pool (10.150.1.43 - 10.150.1.50)
# and deploy NGINX Ingress Controller with MetalLB annotations to request an IP from the pool.

include:
  - /formulas/common/helm/install
  - /formulas/common/k8s-certmanager/install

# Ensure Helm is installed and configured before proceeding
helm_installed:
  test.nop:
    - require:
      - sls: /formulas/common/helm/install

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

# Install or upgrade MetalLB using Helm (without inline config as it's no longer supported)
install_metallb:
  cmd.run:
    - name: |
        helm upgrade --install metallb metallb/metallb \
          --namespace {{ pillar.get('metallb_namespace', 'metallb-system') }} \
          --create-namespace \
          --wait
    - require:
      - k8s: metallb_namespace
      - cmd: update_helm_repos
    - unless: kubectl get deployment -n {{ pillar.get('metallb_namespace', 'metallb-system') }} | grep -q "metallb-controller"

# Configure MetalLB IP pool using IPAddressPool CRD
configure_metallb_ip_pool:
  cmd.run:
    - name: |
        cat <<EOF | kubectl apply -f -
        apiVersion: metallb.io/v1beta1
        kind: IPAddressPool
        metadata:
          name: {{ pillar.get('nginx_ingress_metallb_pool', 'default') }}
          namespace: {{ pillar.get('metallb_namespace', 'metallb-system') }}
        spec:
          addresses:
          - {{ pillar.get('metallb_ip_range_start', '10.150.1.43') }}-{{ pillar.get('metallb_ip_range_end', '10.150.1.50') }}
        EOF
    - require:
      - cmd: install_metallb
    - unless: kubectl get ipaddresspool -n {{ pillar.get('metallb_namespace', 'metallb-system') }} | grep -q "{{ pillar.get('nginx_ingress_metallb_pool', 'default') }}"

# Configure MetalLB L2 Advertisement for the IP pool
configure_metallb_l2_advertisement:
  cmd.run:
    - name: |
        cat <<EOF | kubectl apply -f -
        apiVersion: metallb.io/v1beta1
        kind: L2Advertisement
        metadata:
          name: {{ pillar.get('nginx_ingress_metallb_pool', 'default') }}-l2
          namespace: {{ pillar.get('metallb_namespace', 'metallb-system') }}
        spec:
          ipAddressPools:
          - {{ pillar.get('nginx_ingress_metallb_pool', 'default') }}
        EOF
    - require:
      - cmd: configure_metallb_ip_pool
    - unless: kubectl get l2advertisement -n {{ pillar.get('metallb_namespace', 'metallb-system') }} | grep -q "{{ pillar.get('nginx_ingress_metallb_pool', 'default') }}-l2"

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