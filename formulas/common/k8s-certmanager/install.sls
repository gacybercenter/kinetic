# Ensure the Jetstack Helm repository is available
ensure_jetstack_helm_repo:
  k8s_helm.helm_repo_present:
    - repo_name: jetstack
    - repo_url: https://charts.jetstack.io
    - update_cache: true

{# Gateway API CRDs are not bundled with the cert-manager chart. cert-manager
   needs them to watch HTTPRoute / Gateway (ACME HTTP-01 via HTTPRoute, and
   Gateway listener TLS secrets). Override version/channel/url from pillar
   res-k8s:gateway-api if needed. #}
{% set gateway_api = pillar.get('res-k8s', {}).get('gateway-api', {}) %}
{% set gateway_api_version = gateway_api.get('version', 'v1.4.0') %}
{% set gateway_api_channel = gateway_api.get('channel', 'standard') %}
{% set gateway_api_url = gateway_api.get(
     'url',
     'https://github.com/kubernetes-sigs/gateway-api/releases/download/'
     ~ gateway_api_version ~ '/' ~ gateway_api_channel ~ '-install.yaml'
   ) %}

install_gateway_api_crds:
  cmd.run:
    - name: kubectl apply --server-side --force-conflicts -f {{ gateway_api_url }}
    - require:
      - k8s_helm: ensure_jetstack_helm_repo

# Deploy cert-manager using the k8s_helm module
ensure_certmanager_release:
  k8s_helm.helm_release_present:
    - release_name: cert-manager
    - chart_name: jetstack/cert-manager
    - namespace: cert-manager
    - pillar_key: res-k8s:cert-manager
    - wait_timeout: 300
    - wait_interval: 10
    - set_values:
      - config.gatewayAPI.enabled=true
    - require:
      - k8s_helm: ensure_jetstack_helm_repo
      - cmd: install_gateway_api_crds

ensure_trust_manager_release:
  k8s_helm.helm_release_present:
    - release_name: trust-manager
    - chart_name: oci://quay.io/jetstack/charts/trust-manager
    - namespace: cert-manager
    - pillar_key: res-k8s:trust-manager
    - wait_timeout: 300
    - wait_interval: 10
    - require:
      - k8s_helm: ensure_certmanager_release
