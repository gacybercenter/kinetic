include:
  - /formulas/common/k8s-ingress-controller/install

# Create namespace for MetalLB
metallb_namespace:
  k8s.namespace_present:
    - namespace: {{ pillar.get('metallb_namespace', 'metallb-system') }}

# Define internal and external IPs for the ingress controllers
{% set internal_ip = pillar['res-k8s']['lbs']['ips']['internal'] %}
{% set external_ip = pillar['res-k8s']['lbs']['ips']['external'] %}

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

# # Create a Service for internal ingress controller
# ensure_service_internal:
#   k8s.service_present:
#     - namespace: {{ pillar.get('traefik_internal_namespace', 'internal-ingress') }}
#     - service_name: traefik-internal
#     - service_type: LoadBalancer
#     - selector:
#         app.kubernetes.io/name: traefik
#         app.kubernetes.io/instance: traefik-internal
#     - ports:
#         - name: http
#           port: 80
#           targetPort: 80
#           protocol: TCP
#         - name: https
#           port: 443
#           targetPort: 443
#           protocol: TCP
#     - annotations:
#         metallb.universe.tf/address-pool: lb-pool-internal
#     - require:
#         - k8s: ensure_metallb_advertisement_internal

# # Create a Service for external ingress controller
# ensure_service_external:
#   k8s.service_present:
#     - namespace: {{ pillar.get('traefik_external_namespace', 'external-ingress ') }}
#     - service_name: traefik-external
#     - service_type: LoadBalancer
#     - selector:
#         app.kubernetes.io/name: traefik
#         app.kubernetes.io/instance: traefik-external
#     - ports:
#         - name: http
#           port: 80
#           targetPort: 80
#           protocol: TCP
#         - name: https
#           port: 443
#           targetPort: 443
#           protocol: TCP
#     - annotations:
#         metallb.universe.tf/address-pool: lb-pool-external
#     - require:
#         - k8s: ensure_metallb_advertisement_external
