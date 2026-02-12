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
{% set internal_ip = pillar['res-k8s']['lbs']['internal']['ip'] %}
{% set external_ip = pillar['res-k8s']['lbs']['external']['ip'] %}

# Add the Traefik Ingress Controller Helm repository
add_traefik_ingress_repo:
  k8s_helm.helm_repo_present:
    - repo_name: traefik
    - repo_url: https://traefik.github.io/charts
    - require:
      - test: helm_installed

# Update Helm repositories to ensure the latest charts are available
update_helm_repos:
  cmd.run:
    - name: helm repo update
    - require:
      - k8s_helm: add_metallb_repo
      - k8s_helm: add_traefik_ingress_repo

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

# Install or upgrade Traefik Ingress Controller for internal traffic
install_traefik_internal_ingress_controller:
  k8s_helm.helm_release_present:
    - release_name: traefik-internal
    - chart_name: traefik/traefik
    - namespace: {{ pillar.get('traefik_internal_namespace', 'internal-ingress') }}
    - values_dict:
        logs:
          general:
            level: DEBUG
        service:
          type: {{ pillar.get('traefik_internal_service_type', 'LoadBalancer') }}
          spec:
            loadBalancerIP: {{ internal_ip }}
        replicas: 1
        ingressClass:
          name: traefik-internal
          isDefaultClass: false
        additionalArguments:
          - "--providers.kubernetesIngressNGINX"
          - "--serversTransport.insecureSkipVerify=true"
    - wait_timeout: 300
    - wait_interval: 10
    - require:
      - cmd: update_helm_repos
      - k8s_helm: install_metallb

# Install or upgrade Traefik Ingress Controller for external traffic
install_traefik_external_ingress_controller:
  k8s_helm.helm_release_present:
    - release_name: traefik-external
    - chart_name: traefik/traefik
    - namespace: {{ pillar.get('traefik_external_namespace', 'external-ingress') }}
    - values_dict:
        logs:
          general:
            level: DEBUG
        service:
          type: {{ pillar.get('traefik_external_service_type', 'LoadBalancer') }}
          spec:
            loadBalancerIP: {{ external_ip }}
        replicas: 1
        ingressClass:
          name: traefik-external
          isDefaultClass: false
        additionalArguments:
          - "--providers.kubernetesIngressNGINX"
          - "--serversTransport.insecureSkipVerify=true"
    - wait_timeout: 300
    - wait_interval: 10
    - require:
      - cmd: update_helm_repos
      - k8s_helm: install_metallb