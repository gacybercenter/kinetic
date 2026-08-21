{% set k8s = salt['pillar.get']('k8s') %}
# Step 1: Create namespace for Rook if it doesn't exist
create_rook_namespace:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: |
          kubectl get namespace rook-ceph || kubectl create namespace rook-ceph
    - tgt: '{{ k8s }}'
    - output_loglevel: info

# Step 4: Apply Rook configuration
k8s_rook-op:
  salt.state:
    - tgt: '{{ k8s }}'
    - sls: /formulas/common/k8s-rook/configure
