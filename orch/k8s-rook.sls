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

# Step 2: Label nodes with rook-rsc* as rook-node
label_rook_nodes:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: |
          for node in $(kubectl get nodes -o name | grep 'rook-rsc'); do
            kubectl label $node role=rook-node --overwrite
          done
    - tgt: '{{ k8s }}'
    - output_loglevel: info
    - require:
      - salt: create_rook_namespace

# Step 3: Label nodes with storage* as rook-osd-node
label_storage_nodes:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: |
          for node in $(kubectl get nodes -o name | grep 'storage'); do
            kubectl label $node role=rook-osd-node --overwrite
          done
    - tgt: '{{ k8s }}'
    - output_loglevel: info
    - require:
      - salt: create_rook_namespace

# Step 4: Apply Rook configuration
k8s_rook-op:
  salt.state:
    - tgt: '{{ k8s }}' 
    - sls: /formulas/common/k8s-rook/configure
    - require:
      - salt: label_rook_nodes
      - salt: label_storage_nodes