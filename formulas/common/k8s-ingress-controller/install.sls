# Install MetalLB for LoadBalancer IP management with specified IP pools
# and deploy two Traefik Ingress Controllers for internal and external traffic with MetalLB annotations to request IPs from the pools.
# Use k8s_helm state module for Helm operations.

include:
  - /formulas/common/helm/install

# Ensure Helm is installed and configured before proceeding
helm_installed:
  test.nop:
    - require:
      - sls: /formulas/common/helm/install

# Add the MetalLB Helm repository
add_metallb_repo:
  k8s_helm.helm_repo_present:
    - repo_name: metallb
    - repo_url: https://metallb.github.io/metallb
    - require:
      - test: helm_installed

# Add the Traefik Ingress Controller Helm repository
add_traefik_ingress_repo:
  k8s_helm.helm_repo_present:
    - repo_name: traefik
    - repo_url: https://traefik.github.io/charts
    - require:
      - test: helm_installed

# # Update Helm repositories to ensure the latest charts are available
update_helm_repos:
  cmd.run:
    - name: helm repo update
    - require:
      - k8s_helm: add_metallb_repo
      - k8s_helm: add_traefik_ingress_repo

# # Install or upgrade MetalLB using Helm via k8s_helm state
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

# Install or upgrade Traefik Ingress Controller for external traffic
install_traefik_external_ingress_controller:
  k8s_helm.helm_release_present:
    - release_name: traefik-external
    - chart_name: traefik/traefik
    - namespace: {{ pillar.get('traefik_external_namespace', 'ingress') }}
    - pillar_key: res-k8s:lbs:ingress
    - keep_values_file: True
    - wait_timeout: 300
    - wait_interval: 10
    - require:
      - cmd: update_helm_repos
      - k8s_helm: install_metallb

ext_ingress_tls_certificate:
  k8s.certmanager_certificate_present:
    - name: ext-ingress-tls
    - namespace: external-ingress
    - certificate_name: ext-ingress-tls-secret
    - secret_name: ext-ingress-tls-secret
    - issuer_name: cyberrange-ca-issuer
    - issuer_kind: ClusterIssuer
    - common_name: ext-dashboard.svc.cluster.local
    - dns_names:
      - ext-dashboard.services.gacyberrange.org
    - duration: 2160h
    - renew_before: 360h
    - require:
      - k8s_helm: install_traefik_external_ingress_controller

int_ingress_tls_certificate:
  k8s.certmanager_certificate_present:
    - name: int-ingress-tls
    - namespace: external-ingress
    - certificate_name: int-ingress-tls-secret
    - secret_name: int-ingress-tls-secret
    - issuer_name: cyberrange-ca-issuer
    - issuer_kind: ClusterIssuer
    - common_name: int-dashboard.svc.cluster.local
    - dns_names:
      - int-dashboard.services.gacyberrange.org
    - duration: 2160h
    - renew_before: 360h
    - require:
      - k8s_helm: install_traefik_external_ingress_controller
