include:
  - /formulas/osh-endpoints/install
  - /formulas/common/k8s-nginx-controller/install

# Ensure NGINX Ingress Controller and MetalLB are installed before proceeding
nginx_controller_installed:
  test.nop:
    - require:
      - sls: /formulas/common/k8s-nginx-controller/install

# Create namespace for OpenStack public endpoint (if not already created by NGINX controller)
openstack_namespace:
  k8s.namespace_present:
    - namespace: {{ pillar.get('nginx_ingress_namespace', 'openstack') }}
    - require:
      - test: nginx_controller_installed

# Create a LoadBalancer Service for OpenStack public endpoint with MetalLB annotations
create_openstack_public_service:
  k8s.service_present:
    - name: openstack-public-service
    - namespace: {{ pillar.get('nginx_ingress_namespace', 'openstack') }}
    - service_name: {{ pillar.get('openstack_public_service_name', 'openstack-public') }}
    - service_type: LoadBalancer
    - selector:
        app.kubernetes.io/name: ingress-nginx
        app.kubernetes.io/instance: ingress-nginx
    - ports:
        - name: http
          port: 80
          targetPort: 80
          protocol: TCP
        - name: https
          port: 443
          targetPort: 443
          protocol: TCP
    - annotations:
        metallb.universe.tf/address-pool: {{ pillar.get('nginx_ingress_metallb_pool', 'default') }}
    - require:
      - k8s: openstack_namespace
      - test: nginx_controller_installed

