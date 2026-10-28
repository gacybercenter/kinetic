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

{# Traefik chart creates a GatewayClass. That CRD is not in a stock
   kubeadm cluster. Same install cert-manager uses. #}
{% set gateway_api = pillar.get('res-k8s', {}).get('gateway-api', {}) %}
{% set gateway_api_version = gateway_api.get('version', 'v1.4.0') %}
{# experimental includes TLSRoute/TCPRoute. Traefik lists those by default;
   the standard bundle does not ship them. #}
{% set gateway_api_channel = gateway_api.get('channel', 'experimental') %}
{% set gateway_api_url = gateway_api.get(
     'url',
     'https://github.com/kubernetes-sigs/gateway-api/releases/download/'
     ~ gateway_api_version ~ '/' ~ gateway_api_channel ~ '-install.yaml'
   ) %}

install_gateway_api_crds:
  cmd.run:
    - name: kubectl apply --server-side --force-conflicts -f {{ gateway_api_url }}
    - require:
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
      - cmd: install_gateway_api_crds
      - k8s_helm: install_metallb

{% set ingress_gateways = pillar.get('ingress_gateways', 'both') %}
{% set external_only = ingress_gateways in ['external', ['external']] %}
{% set external_ip = pillar['res-k8s']['lbs']['ips']['external'] %}
{% set gateway_name = 'external' if external_only else 'traefik-external' %}

{% set certs = pillar['res-k8s']['certs']['external'] %}
ext_ingress_tls_certificate:
  k8s.certmanager_certificate_present:
    - name: ext-ingress-tls
    - namespace: ingress
    - certificate_name: {{ certs['name'] }}
    - secret_name: {{ certs['name'] }}-secret
    - issuer_name: {{ certs['issuer'] }}
    - issuer_kind: ClusterIssuer
    - common_name: {{ certs['commonname'] }}
    - dns_names: {{ certs['dns_names'] }}
    - duration: 2160h
    - renew_before: 360h
    - require:
      - k8s_helm: install_traefik_external_ingress_controller

{% if not external_only %}
{% set certs = pillar['res-k8s']['certs']['internal'] %}
int_ingress_tls_certificate:
  k8s.certmanager_certificate_present:
    - name: int-ingress-tls
    - namespace: ingress
    - certificate_name: {{ certs['name'] }}
    - secret_name: {{ certs['name'] }}-secret
    - issuer_name: {{ certs['issuer'] }}
    - issuer_kind: ClusterIssuer
    - common_name: {{ certs['commonname'] }}
    - dns_names: {{ certs['dns_names'] }}
    - duration: 2160h
    - renew_before: 360h
    - require:
      - k8s_helm: install_traefik_external_ingress_controller
{% endif %}

traefik_external_gateway:
  k8s.gateway_present:
    - name: {{ gateway_name }}
    - namespace: ingress
    - gateway_class_name: traefik
    - addresses:
      - type: IPAddress
        value: {{ external_ip }}
    - listeners:
      - name: web-ext
        protocol: HTTP
        port: 9080
        allowedRoutes:
          namespaces:
            from: All
      - name: websecure-ext
        protocol: HTTPS
        port: 9443
        allowedRoutes:
          namespaces:
            from: All
        tls:
          mode: Terminate
          certificateRefs:
            - group: ""
              kind: Secret
              name: ext-ingress-cert-secret
    - require:
      - k8s_helm: install_traefik_external_ingress_controller

{% if not external_only %}
traefik_internal_gateway:
  k8s.gateway_present:
    - name: traefik-internal
    - namespace: ingress
    - gateway_class_name: traefik
    - addresses:
      - type: IPAddress
        value: {{ pillar['res-k8s']['lbs']['ips']['internal'] }}
    - listeners:
      - name: web
        port: 80
        protocol: HTTP
        allowedRoutes:
          namespaces:
            from: All
      - name: websecure
        port: 443
        protocol: HTTPS
        allowedRoutes:
          namespaces:
            from: All
        tls:
          mode: Terminate
          certificateRefs:
            - kind: Secret
              name: int-ingress-cert-secret
              group: ""
    - require:
      - k8s_helm: install_traefik_external_ingress_controller
{% endif %}
