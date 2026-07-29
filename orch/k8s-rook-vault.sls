{% set k8s = salt['pillar.get']('k8s') %}

# Step 1: Install Vault using Helm
k8s_vault_install:
  salt.state:
    - tgt: '{{ k8s }}'
    - sls: formulas.common.k8s-vault

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

# Step 3: Initialize Vault if not already initialized (do not unseal - it will auto-unseal)
# Step 3: Initialize Vault if not already initialized (Azure Key Vault compatible)
initialize_vault:
  salt.function:
    - name: cmd.run
    - tgt: '{{ k8s }}'
    - kwarg:
        cmd: |
          echo "Checking if Vault is initialized using your exact command..."
          INITIALIZED=$(kubectl -n rook-ceph exec -it vault-0 -- vault status 2>/dev/null | grep Initialized | awk '{print $2}')

          if [ "$INITIALIZED" = "false" ] || [ -z "$INITIALIZED" ]; then
            echo "Vault is not initialized. Initializing with Azure Key Vault compatible settings..."
            # For Azure Key Vault auto-unseal, we typically use 5 key shares with threshold of 3
            # The Azure KMS will handle the actual unseal process
            INIT_RESPONSE=$(kubectl -n rook-ceph exec -it vault-0 -- vault operator init -format=json)
            ROOT_TOKEN=$(echo "$INIT_RESPONSE" | jq -r '.root_token')
            echo "Vault initialized successfully."
            echo "Root token: $ROOT_TOKEN"

            # Save token for the configuration script
            echo "export VAULT_TOKEN=$ROOT_TOKEN" > /tmp/.vault-token
            echo "VAULT_TOKEN=$ROOT_TOKEN" >> /tmp/.vault-token

            echo "Vault will be auto-unsealed by Azure Key Vault. Waiting for it to be ready..."
            sleep 15
          else
            echo "Vault is already initialized (status: $INITIALIZED)."
          fi
    - require:
      - salt: wait_for_vault_pods

# Step 4: Run the Vault configuration script
configure_vault_for_rook:
  salt.function:
    - name: cmd.script
    - tgt: '{{ k8s }}'
    - kwarg:
        source: salt://formulas/cmmon/k8s-vault/scripts/vault.sh
        runas: root
    - require:
      - salt: initialize_vault

# Step 4: Verify Vault configuration for Rook
verify_vault_config:
  salt.function:
    - name: cmd.run
    - tgt: '{{ k8s }}'
    - kwarg:
        cmd: |
          echo "Verifying Vault configuration for Rook..."
          kubectl -n rook-ceph exec -it vault-0 -- vault auth list
          kubectl -n rook-ceph exec -it vault-0 -- vault secrets list
          echo "Vault configuration complete. Rook should now be able to authenticate."
    - require:
      - salt: configure_vault_for_rook
