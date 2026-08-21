{% set k8s = salt['pillar.get']('k8s') %}

# Step 2: Assign role label 'node-role.kubernetes.io/rook-node' to nodes with names matching rook-rsc*
assign_rook_node_role:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: |
          for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep 'rook-rsc'); do
            kubectl label nodes "$node" role=rook-node --overwrite
            kubectl label nodes "$node" node-role.kubernetes.io/rook-node= --overwrite
            kubectl taint node "$node" node-role.kubernetes.io/rook-node=:NoSchedule --overwrite
          done
    - tgt: '{{ k8s }}'
    - output_loglevel: info

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
install_rook_cluster:
  salt.state:
    - tgt: {{ k8s }}
    - sls: /formulas/common/k8s-rook/cluster
