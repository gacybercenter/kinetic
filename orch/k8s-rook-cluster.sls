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

# Step 4: Wait for Ceph to be healthy using kubectl rook-ceph plugin (must return HEALTH_OK)
wait_for_ceph_healthy:
  salt.function:
    - name: cmd.run
    - tgt: {{ k8s }}
    - kwarg:
        cmd: |
          echo "Waiting for Ceph cluster to become healthy using kubectl rook-ceph plugin..."
          for i in {1..30}; do
            STATUS=$(kubectl rook-ceph ceph status 2>/dev/null || echo "unavailable")
            if echo "$STATUS" | grep -q "HEALTH_OK"; then
              echo "Ceph cluster is HEALTH_OK - proceeding with pool creation"
              exit 0
            fi
            echo "Attempt $i/30: Ceph status not HEALTH_OK yet, waiting 10s..."
            echo "Current status:"
            echo "$STATUS"
            echo "----------------------------------------"
            sleep 10
          done
          echo "Timeout waiting for Ceph HEALTH_OK after 5 minutes"
          echo "Final status:"
          kubectl rook-ceph ceph status
          exit 1
    - require:
      - salt: install_rook_cluster

# Step 5: Create Ceph pools and StorageClasses once cluster is healthy
create_pools_and_storageclasses:
  salt.state:
    - tgt: {{ k8s }}
    - sls: /formulas/common/k8s-rook/pools
    - require:
      - salt: wait_for_ceph_healthy
