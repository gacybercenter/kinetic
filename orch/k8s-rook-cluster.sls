{% set k8s = salt['pillar.get']('k8s') %}

# Step 2: Assign role label 'node-role.kubernetes.io/rook-node' to nodes with names matching rook-rsc*
assign_rook_node_role:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: |
          for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep 'storage'); do
            kubectl label nodes "$node" node-role.kubernetes.io/rook-node= --overwrite
            kubectl taint node "$node" node-role.kubernetes.io/rook-node=:NoSchedule --overwrite
          done
    - tgt: '{{ k8s }}'
    - output_loglevel: info

install_rook_cluster:
  salt.state:
    - tgt: {{ k8s }}
    - sls: /formulas/common/k8s-rook/cluster
