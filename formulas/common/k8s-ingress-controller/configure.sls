include:
  - /formulas/common/k8s-ingress-controller/install

# Create namespace for MetalLB
metallb_namespace:
  k8s.namespace_present:
    - namespace: {{ pillar.get('metallb_namespace', 'metallb-system') }}

{# ingress_gateways: external skips the internal pool. Default keeps both. #}
{% set ingress_gateways = pillar.get('ingress_gateways', 'both') %}
{% set external_only = ingress_gateways in ['external', ['external']] %}
{% set external_ip = pillar['res-k8s']['lbs']['ips']['external'] %}

{% if not external_only %}
{% set internal_ip = pillar['res-k8s']['lbs']['ips']['internal'] %}
# Configure MetalLB pool and advertisement for internal IP
ensure_metallb_pool_internal:
  k8s.metallb_pool_present:
    - namespace: unused-namespace
    - pool_name: lb-pool-internal
    - addresses:
        - {{ internal_ip }}-{{ internal_ip }}
    - metallb_namespace: metallb-system

ensure_metallb_advertisement_internal:
  k8s.metallb_l2_advertisement_present:
    - namespace: unused-namespace
    - advertisement_name: lb-pool-internal-l2
    - pool_names:
        - lb-pool-internal
    - metallb_namespace: metallb-system
    - require:
        - k8s: ensure_metallb_pool_internal
{% endif %}

# Configure MetalLB pool and advertisement for external IP
ensure_metallb_pool_external:
  k8s.metallb_pool_present:
    - namespace: unused-namespace
    - pool_name: lb-pool-external
    - addresses:
        - {{ external_ip }}-{{ external_ip }}
    - metallb_namespace: metallb-system

ensure_metallb_advertisement_external:
  k8s.metallb_l2_advertisement_present:
    - namespace: unused-namespace
    - advertisement_name: lb-pool-external-l2
    - pool_names:
        - lb-pool-external
    - metallb_namespace: metallb-system
    - require:
        - k8s: ensure_metallb_pool_external
