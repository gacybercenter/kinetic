include:
  - /formulas/common/k8s-nginx-controller/install
  - /formulas/common/k8s-certmanager

# Create namespace for MetalLB
metallb_namespace:
  k8s.namespace_present:
    - namespace: {{ pillar.get('metallb_namespace', 'metallb-system') }}

{% set res_k8s = salt['pillar.get']('res-k8s', {}) %}
{% set lbs = res_k8s.get('lbs', []) %}

# Loop through each load balancer IP in the pillar data
{% for lb_entry in lbs %}
  {% set lb_ip = lb_entry.keys() | first %}
  {% set lb_config = lb_entry[lb_ip] %}
  {% set pool_name = "lb-pool-" + lb_ip.replace('.', '-') %}

# Create a MetalLB IPAddressPool for each IP
ensure_metallb_pool_{{ lb_ip }}:
  k8s.metallb_pool_present:
    - namespace: unused-namespace
    - pool_name: {{ pool_name }}
    - addresses:
        - {{ lb_ip }}-{{ lb_ip }}
    - metallb_namespace: metallb-system

# Create a MetalLB L2Advertisement for each pool
ensure_metallb_advertisement_{{ lb_ip }}:
  k8s.metallb_l2_advertisement_present:
    - namespace: unused-namespace
    - advertisement_name: {{ pool_name }}-l2
    - pool_names:
        - {{ pool_name }}
    - metallb_namespace: metallb-system
    - require:
        - k8s: ensure_metallb_pool_{{ lb_ip }}

# Create a Service associated with this IP using the specific MetalLB pool and dynamic ports from pillar
ensure_service_{{ lb_ip }}:
  k8s.service_present:
    - namespace: openstack
    - service_name: {{ lb_config['service_name'] }}
    - service_type: LoadBalancer
    - selector:
        app.kubernetes.io/name: ingress-nginx
    - ports:
        {% if lb_config.get('ports', []) %}
          {% for port in lb_config.get('ports', []) %}
          - name: {{ 'http' if port == 80 else 'https' if port == 443 else 'port-' + port|string }}
            port: {{ port }}
            targetPort: {{ port }}
            protocol: TCP
          {% endfor %}
        {% else %}
        - name: http
          port: 80
          targetPort: 80
          protocol: TCP
        - name: https
          port: 443
          targetPort: 443
          protocol: TCP
        {% endif %}
    - annotations:
        metallb.universe.tf/address-pool: {{ pool_name }}
    - require:
        - k8s: ensure_metallb_advertisement_{{ lb_ip }}

# Create a Certificate for this service if cert configuration is present in pillar
{% if 'cert' in lb_config %}
ensure_certificate_{{ lb_config['service_name'] }}:
  k8s.certmanager_certificate_present:
    - namespace: {{ pillar.get('nginx_ingress_namespace', 'openstack') }}
    - certificate_name: {{ lb_config['service_name'] }}-tls
    - spec:
        secretName: {{ lb_config['service_name'] }}-tls
        commonName: {{ lb_config['cert']['dns'][0] }}
        dnsNames: {{ lb_config['cert']['dns'] | yaml }}
        issuerRef:
          name: {{ lb_config['cert']['issuer'] }}
          kind: ClusterIssuer
    - annotations:
        description: TLS certificate for {{ lb_config['service_name'] }}
    - require:
        - k8s: ensure_service_{{ lb_ip }}
{% endif %}
{% endfor %}