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

# Step 2: Assign role label 'node-role.kubernetes.io/rook-node' to nodes with names matching rook-rsc*
assign_rook_node_role:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: |
          for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep 'rook-rsc'); do
            kubectl label nodes "$node" node-role.kubernetes.io/rook-node= --overwrite
            kubectl label nodes "$node" ceph-type=mon --overwrite
            kubectl taint node "$node" node-role.kubernetes.io/rook-node=:NoSchedule --overwrite
          done
    - tgt: '{{ k8s }}'
    - output_loglevel: info
    - require:
      - salt: create_rook_namespace

# Step 3: Assign role label 'node-role.kubernetes.io/rook-osd-node' to nodes with names containing storage*
assign_storage_node_role:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: |
          for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep 'storage'); do
            kubectl label nodes "$node" node-role.kubernetes.io/rook-osd-node= --overwrite
            kubectl label nodes "$node" ceph-type=osd --overwrite
            kubectl taint node "$node" node-role.kubernetes.io/rook-osd-node=:NoSchedule --overwrite
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
      - salt: assign_rook_node_role
      - salt: assign_storage_node_role