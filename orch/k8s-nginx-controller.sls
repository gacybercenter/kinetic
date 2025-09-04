{% set k8s = salt['pillar.get']('k8s') %}

# Step 1: Create namespace for EFK if it doesn't exist
create_ingress_namespace:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: |
          kubectl get namespace {{ pillar.get('ingress_namespace', 'nginx-ingress') }} || kubectl create namespace {{ pillar.get('ingress_namespace', 'nginx-ingress') }}
    - tgt: '{{ k8s }}'
    - output_loglevel: info