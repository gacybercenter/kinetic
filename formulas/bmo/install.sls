include:
  - /formulas/common/k8s-certmanager/install

# Ensure required packages are installed
install_prerequisites:
  pkg.installed:
    - pkgs:
        - git
        - curl
        - kubectl
# Create namespace
bmo_ironic_namespace:
  cmd.run:
    - name: kubectl create namespace {{ pillar['bmo_namespace'] }} --dry-run=client -o yaml | kubectl apply -f -
    - unless: kubectl get namespace {{ pillar['bmo_namespace'] }}
    - require:
      - pkg: install_prerequisties

# Clone kustomize manifests for BMO and Ironic
clone_bmo_manifests:
  git.cloned:
    - name: https://github.com/metal3-io/baremetal-operator.git
    - target: /tmp/baremetal-operator
    - branch: main
    - require:
        - pkg: install_prerequisites
# Create kustomization.yaml for BMO and Ironic with basic auth
create_kustomization:
  file.managed:
    - name: /tmp/baremetal-operator/kustomization.yaml
    - contents: |
        apiVersion: kustomize.config.k8s.io/v1beta1
        kind: Kustomization
        resources:
          - config/default
        patches:
          - target:
              kind: Deployment
              name: baremetal-operator
            patch: |
              apiVersion: apps/v1
              kind: Deployment
              metadata:
                name: baremetal-operator
              spec:
                template:
                  spec:
                    containers:
                      - name: baremetal-operator
                        env:
                          - name: IRONIC_AUTH_STRATEGY
                            value: "basic"
                          - name: IRONIC_ENDPOINT
                            value: "{{ pillar['ironic_endpoint_ip'] }}:6385"
    - require:
        - git: clone_bmo_manifests

# Apply kustomize manifests for BMO and Ironic
apply_bmo_manifests:
  cmd.run:
    - name: kubectl apply -k /tmp/baremetal-operator
    - require:
        - file: create_kustomization
        - pkg: install_prerequisites
# Ensure Ironic service is exposed via kube-vip
expose_ironic_service:
  file.managed:
    - name: /tmp/ironic-service.yaml
    - contents: |
        apiVersion: v1
        kind: Service
        metadata:
          name: ironic
          namespace: default
        spec:
          selector:
            app: ironic
          ports:
            - protocol: TCP
              port: 6385
              targetPort: 6385
          type: LoadBalancer
          loadBalancerIP: {{ pillar['ironic_endpoint_ip'] }}
    - require:
        - cmd: apply_bmo_manifests
  cmd.run:
    - name: kubectl apply -f /tmp/ironic-service.yaml
    - require:
        - file: /tmp/ironic-service.yaml