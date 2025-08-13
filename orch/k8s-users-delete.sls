{% set k8s = salt['pillar.get']('k8s') %}
# Define user details (these must be provided via pillar data)
{% set username = salt['pillar.get']('user') %}
{% set access_type = salt['pillar.get']('access_type', 'namespace') %}  # Default to 'namespace'; can be 'cluster-admin'
{% set namespace = salt['pillar.get']('namespace', 'default') %}  # Default namespace if access_type is 'namespace'

# Step 1: Validate access_type to ensure it's either 'cluster-admin' or 'namespace'
validate_access_type:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: |
          if [ "{{ access_type }}" != "cluster-admin" ] && [ "{{ access_type }}" != "namespace" ]; then
            echo "Error: Invalid access_type '{{ access_type }}'. Must be 'cluster-admin' or 'namespace'."
            exit 1
          fi
    - tgt: '{{ k8s }}'
    - output_loglevel: info

# Step 2: Check if user exists in the cluster before attempting deletion
check_user_existence:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: |
          if ! kubectl get csr {{ username }}-csr >/dev/null 2>&1; then
            echo "Warning: Username '{{ username }}' not found (CSR does not exist). Proceeding with cleanup of any remaining resources."
          fi
          echo "Checking for user resources to delete..."
    - tgt: '{{ k8s }}'
    - output_loglevel: info
    - require:
      - salt: validate_access_type

# Step 3: Delete the user's CSR if it exists
delete_user_csr:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: |
          if kubectl get csr {{ username }}-csr >/dev/null 2>&1; then
            kubectl delete csr {{ username }}-csr
            echo "Deleted CSR for '{{ username }}'."
          else
            echo "No CSR found for '{{ username }}'."
          fi
    - tgt: '{{ k8s }}'
    - output_loglevel: info
    - require:
      - salt: check_user_existence

# Step 4: Conditionally delete RBAC resources based on access_type
{% if access_type == 'cluster-admin' %}
delete_cluster_admin_rolebinding:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: |
          if kubectl get clusterrolebinding {{ username }}-cluster-admin-binding >/dev/null 2>&1; then
            kubectl delete clusterrolebinding {{ username }}-cluster-admin-binding
            echo "Deleted ClusterRoleBinding for '{{ username }}'."
          else
            echo "No ClusterRoleBinding found for '{{ username }}'."
          fi
    - tgt: '{{ k8s }}'
    - output_loglevel: info
    - require:
      - salt: delete_user_csr
{% else %}
delete_namespace_rolebinding:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: |
          if kubectl get rolebinding {{ username }}-rolebinding -n {{ namespace }} >/dev/null 2>&1; then
            kubectl delete rolebinding {{ username }}-rolebinding -n {{ namespace }}
            echo "Deleted RoleBinding for '{{ username }}' in namespace '{{ namespace }}'."
          else
            echo "No RoleBinding found for '{{ username }}' in namespace '{{ namespace }}'."
          fi
    - tgt: '{{ k8s }}'
    - output_loglevel: info
    - require:
      - salt: delete_user_csr

delete_namespace_role:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: |
          if kubectl get role {{ username }}-role -n {{ namespace }} >/dev/null 2>&1; then
            kubectl delete role {{ username }}-role -n {{ namespace }}
            echo "Deleted Role for '{{ username }}' in namespace '{{ namespace }}'."
          else
            echo "No Role found for '{{ username }}' in namespace '{{ namespace }}'."
          fi
    - tgt: '{{ k8s }}'
    - output_loglevel: info
    - require:
      - salt: delete_namespace_rolebinding
{% endif %}

# Step 5: Clean up user files (key, csr, crt, kubeconfig) if they exist on the node
cleanup_user_files:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: |
          for file in /tmp/{{ username }}.key /tmp/{{ username }}.csr /tmp/{{ username }}.crt /tmp/{{ username }}.kubeconfig; do
            if [ -f "$file" ]; then
              rm -f "$file"
              echo "Deleted file: $file"
            else
              echo "File not found: $file"
            fi
          done
    - tgt: '{{ k8s }}'
    - output_loglevel: info
    - require:
      {% if access_type == 'cluster-admin' %}
      - salt: delete_cluster_admin_rolebinding
      {% else %}
      - salt: delete_namespace_role
      {% endif %}

# Step 6: Log completion of user deletion
log_deletion_completion:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: echo "User '{{ username }}' deletion process completed. Access type was '{{ access_type }}'."
    - tgt: '{{ k8s }}'
    - output_loglevel: info
    - require:
      - salt: cleanup_user_files