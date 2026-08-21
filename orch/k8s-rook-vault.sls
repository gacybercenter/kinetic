{% set k8s = salt['pillar.get']('k8s') %}

# Step 1: Install Vault using Helm (install.sls only - configure runs after init)
k8s_vault_install:
  salt.state:
    - tgt: '{{ k8s }}'
    - sls: formulas.common.k8s-vault.install

# Step 2: Wait for Vault pods to be ready
wait_for_vault_pods:
  salt.function:
    - name: cmd.run
    - tgt: '{{ k8s }}'
    - kwarg:
        cmd: |
          echo "Waiting for Vault pods to be ready..."
          for i in {1..30}; do
            POD_STATUS=$(kubectl -n rook-ceph get pods -l app.kubernetes.io/name=vault -o jsonpath='{.items[*].status.phase}' 2>/dev/null || echo "Pending")
            if echo "$POD_STATUS" | grep -q "Running"; then
              echo "Vault pods are running"
              exit 0
            fi
            echo "Attempt $i/30: Vault pods not ready yet, waiting 10s..."
            sleep 10
          done
          echo "Timeout waiting for Vault pods to be ready"
          exit 1
    - require:
      - salt: k8s_vault_install

# Step 3: Initialize Vault via the kinetic_vault module (Azure Key Vault auto-unseal)
# Init material (root token + keys) is stored in the 'vault-init' k8s Secret.
initialize_vault:
  salt.function:
    - name: kinetic_vault.initialize
    - tgt: '{{ k8s }}'
    - kwarg:
        vault_addr: k8s://rook-ceph/vault:8200
        namespace: rook-ceph
        secret_name: vault-init
    - require:
      - salt: wait_for_vault_pods

# Step 4: Configure Vault for Rook (k8s auth, policies, roles, break-glass AppRole)
# Replaces the old vault.sh script with idempotent vault.* states.
configure_vault_for_rook:
  salt.state:
    - tgt: '{{ k8s }}'
    - sls: formulas.common.k8s-vault.configure
    - require:
      - salt: initialize_vault

# Step 5: Verify Vault configuration for Rook
verify_vault_config:
  salt.function:
    - name: kinetic_vault.status
    - tgt: '{{ k8s }}'
    - kwarg:
        vault_addr: k8s://rook-ceph/vault:8200
    - require:
      - salt: configure_vault_for_rook
